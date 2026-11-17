#!/usr/bin/env bash
# Create/update one hospital realm: clients + persona client-roles + theme + logo attr.
# Personas are identical every run (from keycloak/hospital-onboarding/personas.json).
# Permissions matrix is NOT created here — that lives in org DB (see sync script).
set -euo pipefail

ENV_FILE="${1:?usage: $0 path/to/hospital.env}"
# shellcheck disable=SC1090
set -a && source "$ENV_FILE" && set +a

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERSONAS_FILE="$ROOT/keycloak/hospital-onboarding/personas.json"

: "${KC_URL:?}"
: "${KC_ADMIN_USER:?}"
: "${KC_ADMIN_PASSWORD:?}"
: "${HOSPITAL_SLUG:?}"
: "${HOSPITAL_DISPLAY_NAME:?}"

REALM="hospital-${HOSPITAL_SLUG}"
LOGIN_THEME="${LOGIN_THEME:-xelerait}"
RACC_CLIENT_ID="${RACC_CLIENT_ID:-racc}"
POD_CLIENT_ID="${POD_CLIENT_ID:-pod}"
POD_ENABLED="${POD_ENABLED:-false}"

need() { command -v "$1" >/dev/null || { echo "need $1 on PATH" >&2; exit 1; }; }
need curl
need jq

echo "==> Admin token"
TOKEN="$(curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${KC_ADMIN_USER}" \
  -d "password=${KC_ADMIN_PASSWORD}" \
  -d "grant_type=password" | jq -r .access_token)"
[[ "$TOKEN" != "null" && -n "$TOKEN" ]] || { echo "failed to get admin token" >&2; exit 1; }

auth=(-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json")

echo "==> Realm ${REALM}"
if curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}" >/dev/null 2>&1; then
  echo "    exists — updating displayName / theme / logo"
  curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}" > /tmp/realm.json
  SSL_REQUIRED="${SSL_REQUIRED:-none}"
  jq --arg dn "$HOSPITAL_DISPLAY_NAME" --arg theme "$LOGIN_THEME" --arg logo "${LOGIN_LOGO_URL:-}" --arg ssl "$SSL_REQUIRED" '
    .displayName = $dn
    | .loginTheme = $theme
    | .sslRequired = $ssl
    | .attributes = (.attributes // {})
    | if $logo != "" then .attributes.loginLogoUrl = $logo else . end
  ' /tmp/realm.json > /tmp/realm2.json
  curl -sf -X PUT "${auth[@]}" "${KC_URL}/admin/realms/${REALM}" -d @/tmp/realm2.json
else
  echo "    creating"
  # sslRequired=none for HTTP-dev VMs (KC_HTTP_ENABLED). Use external/all in prod HTTPS.
  SSL_REQUIRED="${SSL_REQUIRED:-none}"
  jq -n \
    --arg realm "$REALM" \
    --arg dn "$HOSPITAL_DISPLAY_NAME" \
    --arg theme "$LOGIN_THEME" \
    --arg logo "${LOGIN_LOGO_URL:-}" \
    --arg ssl "$SSL_REQUIRED" \
    '{
      realm: $realm,
      displayName: $dn,
      enabled: true,
      sslRequired: $ssl,
      registrationAllowed: false,
      loginTheme: $theme,
      attributes: (if $logo != "" then {loginLogoUrl: $logo} else {} end)
    }' | curl -sf -X POST "${auth[@]}" "${KC_URL}/admin/realms" -d @-
fi

upsert_client() {
  local cid="$1" root="$2" redirects="$3" origins="$4" enabled="$5"
  local list uuid
  list="$(curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/clients?clientId=${cid}")"
  uuid="$(echo "$list" | jq -r '.[0].id // empty')"
  local body
  body="$(jq -n \
    --arg cid "$cid" \
    --arg root "$root" \
    --argjson enabled "$enabled" \
    --arg redirects "$redirects" \
    --arg origins "$origins" \
    '{
      clientId: $cid,
      name: $cid,
      enabled: $enabled,
      publicClient: true,
      standardFlowEnabled: true,
      directAccessGrantsEnabled: false,
      rootUrl: $root,
      redirectUris: ($redirects | split(" ")),
      webOrigins: ($origins | split(" ")),
      attributes: { "pkce.code.challenge.method": "S256" }
    }')"
  if [[ -n "$uuid" ]]; then
    echo "    client ${cid} — update"
    curl -sf -X PUT "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/clients/${uuid}" -d "$body" >/dev/null
  else
    echo "    client ${cid} — create"
    curl -sf -X POST "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/clients" -d "$body" >/dev/null
  fi
}

echo "==> Clients"
upsert_client "$RACC_CLIENT_ID" \
  "${RACC_ROOT_URL:-}" \
  "${RACC_REDIRECT_URIS:-*}" \
  "${RACC_WEB_ORIGINS:-+}" \
  true

if [[ "$POD_ENABLED" == "true" ]]; then
  upsert_client "$POD_CLIENT_ID" \
    "${POD_ROOT_URL:-}" \
    "${POD_REDIRECT_URIS:-*}" \
    "${POD_WEB_ORIGINS:-+}" \
    true
else
  upsert_client "$POD_CLIENT_ID" \
    "${POD_ROOT_URL:-}" \
    "${POD_REDIRECT_URIS:-*}" \
    "${POD_WEB_ORIGINS:-+}" \
    false
fi

echo "==> Persona client roles on ${RACC_CLIENT_ID} (same pack every hospital)"
RACC_UUID="$(curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/clients?clientId=${RACC_CLIENT_ID}" | jq -r '.[0].id')"
[[ -n "$RACC_UUID" && "$RACC_UUID" != "null" ]] || { echo "racc client missing" >&2; exit 1; }

jq -c '.personas[]' "$PERSONAS_FILE" | while read -r row; do
  key="$(echo "$row" | jq -r .key)"
  label="$(echo "$row" | jq -r .label)"
  role="persona-${key}"
  if curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/clients/${RACC_UUID}/roles/${role}" >/dev/null 2>&1; then
    echo "    role ${role} exists"
  else
    echo "    role ${role} create"
    jq -n --arg name "$role" --arg desc "$label" \
      '{name: $name, description: $desc}' \
      | curl -sf -X POST "${auth[@]}" \
        "${KC_URL}/admin/realms/${REALM}/clients/${RACC_UUID}/roles" -d @- >/dev/null
  fi
done

echo "==> Done. Realm=${REALM}"
echo "    Assign users persona-* roles in Admin Console (or API)."
echo "    Run sync-kc-personas-to-orgdb.sh to mirror into org DB + seed matrix keys."
