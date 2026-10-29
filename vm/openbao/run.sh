#!/usr/bin/env bash
set -euo pipefail

# Prompt vault: Transit unsealer + OpenBao. Keycloak is ../keycloak/.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
mkdir -p secrets logs

if [ ! -f .env ]; then
  echo "Missing .env — copy .env.example and set OPENBAO_HOSTNAME." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

OPENBAO_HOSTNAME="${OPENBAO_HOSTNAME:-localhost}"
OPENBAO_HOST_PORT="${OPENBAO_HOST_PORT:-8200}"
OPENBAO_API_ADDR="${OPENBAO_API_ADDR:-https://${OPENBAO_HOSTNAME}:${OPENBAO_HOST_PORT}}"

compose() { docker compose -f docker-compose.yml "$@"; }

echo "==> 1/5 TLS certs"
./generate-vm-certs.sh

echo "==> 2/5 Starting Transit unsealer"
compose up -d openbao-unsealer

echo "==> 3/5 Waiting for the unsealer API"
until compose exec -T openbao-unsealer bao status >/tmp/pv-unsealer-status.txt 2>&1 || [ "$?" -eq 2 ]; do
  sleep 1
done

UNSEALER_STATUS="$(compose exec -T openbao-unsealer bao status 2>&1 || true)"
if echo "$UNSEALER_STATUS" | grep -qi "Initialized.*false"; then
  echo "    Initializing unsealer (1-of-1 Shamir — root of auto-unseal)."
  INIT_OUT="$(compose exec -T openbao-unsealer bao operator init -key-shares=1 -key-threshold=1)"
  UNSEAL_KEY="$(echo "$INIT_OUT" | grep -i 'Unseal Key 1:' | awk '{print $NF}')"
  ROOT_TOKEN="$(echo "$INIT_OUT" | grep -i 'Initial Root Token:' | awk '{print $NF}')"
  printf '%s' "$UNSEAL_KEY" > secrets/unsealer-unseal-key.txt
  printf '%s' "$ROOT_TOKEN" > secrets/unsealer-root-token.txt
  chmod 600 secrets/unsealer-unseal-key.txt secrets/unsealer-root-token.txt
  compose exec -T openbao-unsealer bao operator unseal "$UNSEAL_KEY"
else
  echo "    Already initialized."
  if echo "$UNSEALER_STATUS" | grep -qi "Sealed.*true"; then
    compose exec -T openbao-unsealer bao operator unseal "$(cat secrets/unsealer-unseal-key.txt)"
  fi
fi
ROOT_TOKEN="$(cat secrets/unsealer-root-token.txt)"

echo "==> 4/5 Transit key + unseal token, start OpenBao"
compose exec -T -e BAO_TOKEN="$ROOT_TOKEN" openbao-unsealer bao secrets enable transit 2>/dev/null || true
compose exec -T -e BAO_TOKEN="$ROOT_TOKEN" openbao-unsealer bao write -f transit/keys/prompt-vault-unseal type=aes256-gcm96

cat > /tmp/pv-unseal-policy.hcl <<'EOF'
path "transit/encrypt/prompt-vault-unseal" { capabilities = ["update"] }
path "transit/decrypt/prompt-vault-unseal" { capabilities = ["update"] }
EOF
compose cp /tmp/pv-unseal-policy.hcl openbao-unsealer:/tmp/unseal-policy.hcl
MSYS_NO_PATHCONV=1 compose exec -T -e BAO_TOKEN="$ROOT_TOKEN" openbao-unsealer bao policy write prompt-vault-unseal /tmp/unseal-policy.hcl

if [ ! -f secrets/unsealer-client-token.txt ]; then
  compose exec -T -e BAO_TOKEN="$ROOT_TOKEN" openbao-unsealer \
    bao token create -policy=prompt-vault-unseal -orphan -period=768h -field=token \
    > secrets/unsealer-client-token.txt
  chmod 600 secrets/unsealer-client-token.txt
fi
UNSEALER_TOKEN="$(cat secrets/unsealer-client-token.txt)"

sed -e "s|__UNSEALER_TOKEN__|${UNSEALER_TOKEN}|g" \
    -e "s|__OPENBAO_API_ADDR__|${OPENBAO_API_ADDR}|g" \
    config.hcl.tmpl > config.hcl
compose up -d openbao

echo "==> 5/5 Initializing OpenBao (Transit auto-unseals it)"
until compose exec -T openbao bao status >/tmp/pv-openbao-status.txt 2>&1 || [ "$?" -eq 2 ]; do
  sleep 1
done
MAIN_STATUS="$(compose exec -T openbao bao status 2>&1 || true)"
if echo "$MAIN_STATUS" | grep -qi "Initialized.*false"; then
  MAIN_INIT_OUT="$(compose exec -T openbao bao operator init -recovery-shares=1 -recovery-threshold=1)"
  MAIN_RECOVERY_KEY="$(echo "$MAIN_INIT_OUT" | grep -i 'Recovery Key 1:' | awk '{print $NF}')"
  MAIN_ROOT_TOKEN="$(echo "$MAIN_INIT_OUT" | grep -i 'Initial Root Token:' | awk '{print $NF}')"
  printf '%s' "$MAIN_RECOVERY_KEY" > secrets/openbao-recovery-key.txt
  printf '%s' "$MAIN_ROOT_TOKEN" > secrets/openbao-root-token.txt
  chmod 600 secrets/openbao-recovery-key.txt secrets/openbao-root-token.txt
  echo "    Recovery key in secrets/openbao-recovery-key.txt — not needed for restarts."
else
  echo "    Already initialized."
fi

echo
echo "==> OpenBao is up."
echo "    ${OPENBAO_API_ADDR}  (root: secrets/openbao-root-token.txt)"
echo "    Unsealer: loopback :${UNSEALER_HOST_PORT:-8220} only"
echo "    Next: ../../scripts/bootstrap_openbao.sh"
echo "    KEYCLOAK_OIDC_HOST=host.docker.internal:8080  KEYCLOAK_OIDC_SCHEME=http"
echo "    After reboot: ./run.sh again."
