#!/usr/bin/env bash
set -euo pipefail

# Issues one leaf certificate signed by a CA from generate_ca.sh.
#
# Usage:
#   issue_cert.sh <ca-dir> <common-name> <output-dir> [sans]
#
# <ca-dir>      directory containing ca.key and ca.crt
# <common-name> e.g. "nursing-assistant-agent.agents.internal" for an
#               agent cert, or the real hostname for a server cert
# [sans]        only needed for SERVER certs, so TLS hostname
#               verification passes - e.g.
#               "DNS:keycloak.internal.example.com,IP:10.0.0.5"
#               Leave blank for agent/on-call client certs - those are
#               matched by Common Name (allowed_common_names on the
#               OpenBao side), not SAN.
#
# Produces <output-dir>/<common-name>.key and <output-dir>/<common-name>.crt
#
# Requires: openssl.

CA_DIR="${1:?usage: issue_cert.sh <ca-dir> <common-name> <output-dir> [sans]}"
CN="${2:?missing common-name}"
OUT_DIR="${3:?missing output-dir}"
SANS="${4:-}"
DAYS="${CERT_VALIDITY_DAYS:-825}"

mkdir -p "$OUT_DIR"
# printf, not echo - echo appends a trailing newline that `tr -c` would
# otherwise convert into a stray trailing underscore in the filename
# (caught by actually running this script, not just reading it).
SAFE_NAME="$(printf '%s' "$CN" | tr -c 'A-Za-z0-9._-' '_')"
KEY="$OUT_DIR/${SAFE_NAME}.key"
CSR="$OUT_DIR/${SAFE_NAME}.csr"
CRT="$OUT_DIR/${SAFE_NAME}.crt"

openssl req -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CSR" -subj "/CN=${CN}"

if [ -n "$SANS" ]; then
  EXT_FILE="$OUT_DIR/${SAFE_NAME}-ext.cnf"
  cat > "$EXT_FILE" <<EOF
[v3_req]
subjectAltName = ${SANS}
EOF
  openssl x509 -req -in "$CSR" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
    -CAcreateserial -out "$CRT" -days "$DAYS" \
    -extfile "$EXT_FILE" -extensions v3_req
else
  openssl x509 -req -in "$CSR" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
    -CAcreateserial -out "$CRT" -days "$DAYS"
fi

rm -f "$CSR"
chmod 600 "$KEY"
echo "Issued: $CRT (CN=${CN}, valid ${DAYS} days)"
