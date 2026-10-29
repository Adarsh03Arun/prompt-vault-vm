#!/usr/bin/env bash
set -euo pipefail

# Generates one self-signed CA: a private key and a certificate with the
# extensions a modern OpenSSL actually requires to treat it as a valid
# CA (basicConstraints + keyUsage). Not theoretical - the first throwaway
# CA generated during this project's own integration testing (2026-10-25)
# lacked these, and every chain validation against it failed with "CA
# cert does not include key usage extension".
#
# This project needs (at least) three SEPARATE CAs - never reuse one
# across these, each is its own trust domain:
#   1. Server TLS CA   - signs the HTTPS certs for the Keycloak and
#                         OpenBao VMs (see ../../keycloak/VM-SETUP.md and
#                         ../../openbao/VM-SETUP.md)
#   2. Agent client CA - signs AI agent certs for OpenBao's auth/cert
#                         method (AGENT_CA_CERT_PATH in
#                         ../bootstrap_openbao.sh)
#   3. On-call CA      - signs break-glass kill-switch certs, kept
#                         deliberately separate from agent certs
#                         (ONCALL_CA_CERT_PATH in ../bootstrap_openbao.sh)
#
# Usage: generate_ca.sh <common-name> <output-dir>
# Produces <output-dir>/ca.key and <output-dir>/ca.crt
#
# Requires: openssl.

CN="${1:?usage: generate_ca.sh <common-name> <output-dir>}"
OUT_DIR="${2:?missing output-dir}"
DAYS="${CA_VALIDITY_DAYS:-3650}"

mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/ca-ext.cnf" <<EOF
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$OUT_DIR/ca.key" \
  -out "$OUT_DIR/ca.crt" \
  -days "$DAYS" \
  -subj "/CN=${CN}" \
  -extensions v3_ca -config "$OUT_DIR/ca-ext.cnf"

chmod 600 "$OUT_DIR/ca.key"
echo "CA created: $OUT_DIR/ca.crt (CN=${CN}, valid ${DAYS} days)"
echo "Keep $OUT_DIR/ca.key offline/secured - anything signed by it is trusted."
