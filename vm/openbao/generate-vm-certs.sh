#!/usr/bin/env bash
set -euo pipefail

# One CA, two leaves (OpenBao + Transit unsealer). Run by ./run.sh.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [ -f certs/ca/ca.crt ]; then
  echo "certs/ca/ca.crt already exists - skipping. Delete certs/ to regenerate."
  exit 0
fi

if [ -f "$ROOT/../../scripts/pki/generate_ca.sh" ]; then
  SCRIPTS="$ROOT/../../scripts"
elif [ -f "$ROOT/scripts/pki/generate_ca.sh" ]; then
  SCRIPTS="$ROOT/scripts"
else
  echo "Missing PKI scripts. Copy identity-vault/scripts next to this folder as ./scripts (or keep the full identity-vault tree)." >&2
  exit 1
fi

OPENBAO_HOSTNAME="${OPENBAO_HOSTNAME:-localhost}"
OPENBAO_SANS="DNS:openbao,DNS:localhost,IP:127.0.0.1,DNS:${OPENBAO_HOSTNAME}"
UNSEALER_SANS="DNS:openbao-unsealer,DNS:localhost,IP:127.0.0.1"
if [ -n "${OPENBAO_EXTRA_SANS:-}" ]; then
  OPENBAO_SANS="${OPENBAO_SANS},${OPENBAO_EXTRA_SANS}"
fi

"$SCRIPTS/pki/generate_ca.sh" "Prompt Vault VM CA" certs/ca
cp certs/ca/ca.crt certs/ca.crt

"$SCRIPTS/issue_cert.sh" certs/ca openbao certs/leaf "$OPENBAO_SANS"
"$SCRIPTS/issue_cert.sh" certs/ca openbao-unsealer certs/leaf "$UNSEALER_SANS"

cp certs/leaf/openbao.crt certs/openbao.crt
cp certs/leaf/openbao.key certs/openbao.key
cp certs/leaf/openbao-unsealer.crt certs/openbao-unsealer.crt
cp certs/leaf/openbao-unsealer.key certs/openbao-unsealer.key

echo "VM certs ready in certs/ (ca.crt, openbao.{crt,key}, openbao-unsealer.{crt,key})."
