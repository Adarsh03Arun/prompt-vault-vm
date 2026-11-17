#!/usr/bin/env bash
# Sync Keycloak → Org DB:
#   1) Ensure persona catalog rows exist (role_key = persona key)
#   2) Upsert users from KC (external_subject = sub, role from persona-* client role)
#
# Org DB is source of truth for the *permission matrix cells*.
# Keycloak is source of truth for *which persona a user has*.
#
# Requires: curl, jq, psql
# Schema assumptions (adjust SQL if your tables differ):
#   roles(role_key UNIQUE, label, category)
#   users(external_subject UNIQUE, hospital_id, role_id FK → roles)
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
: "${HOSPITAL_ID:?}"
: "${ORG_DB_HOST:?}"
: "${ORG_DB_NAME:?}"
: "${ORG_DB_USER:?}"
: "${ORG_DB_PASSWORD:?}"

REALM="hospital-${HOSPITAL_SLUG}"
RACC_CLIENT_ID="${RACC_CLIENT_ID:-racc}"
ORG_DB_PORT="${ORG_DB_PORT:-5432}"

need() { command -v "$1" >/dev/null || { echo "need $1 on PATH" >&2; exit 1; }; }
need curl
need jq
need psql

export PGPASSWORD="$ORG_DB_PASSWORD"
PSQL=(psql -h "$ORG_DB_HOST" -p "$ORG_DB_PORT" -U "$ORG_DB_USER" -d "$ORG_DB_NAME" -v ON_ERROR_STOP=1)

echo "==> Admin token"
TOKEN="$(curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${KC_ADMIN_USER}" \
  -d "password=${KC_ADMIN_PASSWORD}" \
  -d "grant_type=password" | jq -r .access_token)"
auth=(-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json")

echo "==> Seed persona catalog into org DB (idempotent)"
jq -c '.personas[]' "$PERSONAS_FILE" | while read -r row; do
  key="$(echo "$row" | jq -r .key)"
  label="$(echo "$row" | jq -r .label)"
  category="$(echo "$row" | jq -r .category)"
  "${PSQL[@]}" -c \
    "INSERT INTO roles (role_key, label, category)
     VALUES ('${key}', '${label}', '${category}')
     ON CONFLICT (role_key) DO UPDATE
       SET label = EXCLUDED.label, category = EXCLUDED.category;"
done

echo "==> Pull KC users and mirror persona → org users"
RACC_UUID="$(curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/clients?clientId=${RACC_CLIENT_ID}" | jq -r '.[0].id')"
USERS="$(curl -sf "${auth[@]}" "${KC_URL}/admin/realms/${REALM}/users?max=500")"

echo "$USERS" | jq -c '.[]' | while read -r u; do
  uid="$(echo "$u" | jq -r .id)"
  sub="$uid"   # Keycloak user id == JWT sub for local users
  username="$(echo "$u" | jq -r .username)"
  roles="$(curl -sf "${auth[@]}" \
    "${KC_URL}/admin/realms/${REALM}/users/${uid}/role-mappings/clients/${RACC_UUID}" || echo '[]')"
  persona="$(echo "$roles" | jq -r '[.[].name | select(startswith("persona-"))] | first // empty' | sed 's/^persona-//')"
  if [[ -z "$persona" ]]; then
    echo "    skip ${username}: no persona-* role"
    continue
  fi
  echo "    upsert ${username} → persona=${persona} hospital=${HOSPITAL_ID}"
  "${PSQL[@]}" -c \
    "INSERT INTO users (external_subject, hospital_id, role_id)
     SELECT '${sub}', '${HOSPITAL_ID}', r.id FROM roles r WHERE r.role_key = '${persona}'
     ON CONFLICT (external_subject) DO UPDATE
       SET hospital_id = EXCLUDED.hospital_id,
           role_id = EXCLUDED.role_id;"
done

echo "==> Sync done. Edit permission matrix in org DB only; re-run after persona changes in KC."
