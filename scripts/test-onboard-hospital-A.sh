#!/usr/bin/env bash
# Smoke-test hospital onboard → realm hospital-A
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$ROOT/keycloak/hospital-onboarding/hospital-A.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing env: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a && source "$ENV_FILE" && set +a

if [[ "${KC_ADMIN_PASSWORD:-REPLACE_ME}" == "REPLACE_ME" || -z "${KC_ADMIN_PASSWORD:-}" ]]; then
  echo "Set KC_ADMIN_PASSWORD in $ENV_FILE (not REPLACE_ME), then re-run." >&2
  exit 1
fi

chmod +x "$ROOT/scripts/onboard-hospital.sh"
"$ROOT/scripts/onboard-hospital.sh" "$ENV_FILE"

REALM="hospital-${HOSPITAL_SLUG}"
echo
echo "==> Verify"
TOKEN="$(curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${KC_ADMIN_USER}" \
  -d "password=${KC_ADMIN_PASSWORD}" \
  -d "grant_type=password" | jq -r .access_token)"

curl -sf -H "Authorization: Bearer ${TOKEN}" "${KC_URL}/admin/realms/${REALM}" \
  | jq '{realm, displayName, loginTheme, attributes}'

echo
echo "Clients:"
curl -sf -H "Authorization: Bearer ${TOKEN}" "${KC_URL}/admin/realms/${REALM}/clients" \
  | jq -r '.[].clientId' | grep -E '^(racc|pod)$' || true

RACC_UUID="$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "${KC_URL}/admin/realms/${REALM}/clients?clientId=racc" | jq -r '.[0].id')"
echo
echo "Persona roles on racc (expect 13):"
curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "${KC_URL}/admin/realms/${REALM}/clients/${RACC_UUID}/roles" \
  | jq -r '.[].name' | grep '^persona-' | sort

echo
echo "Login preview (from a browser that can reach KC):"
echo "  ${KC_URL}/realms/${REALM}/account/"
