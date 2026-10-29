#!/usr/bin/env bash
set -euo pipefail

# Shared IAM: Keycloak + its Postgres. Same VM as OpenBao, separate folder.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ ! -f .env ]; then
  echo "Missing .env — copy .env.example and set KEYCLOAK_ADMIN_PASSWORD / KEYCLOAK_DB_PASSWORD." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"
: "${KEYCLOAK_DB_PASSWORD:?set KEYCLOAK_DB_PASSWORD in .env}"
if [ "$KEYCLOAK_ADMIN_PASSWORD" = "REPLACE_ME" ] || [ "$KEYCLOAK_DB_PASSWORD" = "REPLACE_ME" ]; then
  echo "Replace REPLACE_ME passwords in .env (admin and DB passwords must differ)." >&2
  exit 1
fi
if [ "$KEYCLOAK_ADMIN_PASSWORD" = "$KEYCLOAK_DB_PASSWORD" ]; then
  echo "KEYCLOAK_ADMIN_PASSWORD and KEYCLOAK_DB_PASSWORD must not be the same." >&2
  exit 1
fi

if [ ! -f realm-export.json ]; then
  SRC="$ROOT/../../keycloak/realm-export.json"
  if [ -f "$SRC" ]; then
    cp "$SRC" realm-export.json
  else
    echo "Missing realm-export.json — copy identity-vault/keycloak/realm-export.json into this folder." >&2
    exit 1
  fi
fi

docker compose -f docker-compose.yml up -d

echo
echo "==> Keycloak is up (shared IAM)."
echo "    http://${KEYCLOAK_HOSTNAME:-localhost}:${KEYCLOAK_HOST_PORT:-8080}"
echo "    Postgres is loopback :${KEYCLOAK_DB_HOST_PORT:-5432} only."
echo "    Next: ../openbao/run.sh  then  ../../scripts/bootstrap_keycloak.sh"
