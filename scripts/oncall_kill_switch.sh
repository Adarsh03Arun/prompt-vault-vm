#!/usr/bin/env bash
set -euo pipefail

# The break-glass kill switch itself - deliberately independent of
# Keycloak and the Admin UI backend (see ../CONTEXT.md's "Kill-switch vs.
# reinstatement asymmetry" and openbao/policies/kill_switch/README.md).
# Talks to OpenBao's HTTP API directly over mTLS - no browser, no Admin
# UI, no Keycloak anywhere in this chain, so it works even if either of
# those is the thing that's down.
#
# Soft-delete only - NEVER destroy. This is what makes the rare
# two-person reinstatement (via the normal Keycloak-gated Admin UI path)
# possible afterward. See docs/design/openbao-api-reference.md §10.
#
# Usage:
#   oncall_kill_switch.sh <openbao-url> <client-cert> <client-key> \
#       <environment> <space> <agent_name> <version> [<version>...]
#
# Prereqs: the client cert's CN must match the oncall-kill-switch auth/cert
# role's allowed_common_names (see scripts/bootstrap_openbao.sh), and the
# identity should already be registered via
# scripts/register_oncall_identity.sh so this is attributable in the audit
# log, not anonymous.
#
# Requires: curl, jq.

URL="${1:?usage: oncall_kill_switch.sh <url> <cert> <key> <env> <space> <agent> <version...>}"
CERT="${2:?missing client cert path}"
KEY="${3:?missing client key path}"
ENVIRONMENT="${4:?missing environment}"
SPACE="${5:?missing space}"
AGENT_NAME="${6:?missing agent_name}"
shift 6
[ "$#" -ge 1 ] || { echo "at least one version is required" >&2; exit 1; }
VERSIONS_JSON="$(printf '%s\n' "$@" | jq -R 'tonumber' | jq -s .)"

echo "==> Logging in via auth/cert (mTLS - no Keycloak involved on this path)"
LOGIN_RESPONSE="$(curl -sS --cert "$CERT" --key "$KEY" -X POST "${URL}/v1/auth/cert/login")"
TOKEN="$(echo "$LOGIN_RESPONSE" | jq -r '.auth.client_token // empty')"
if [ -z "$TOKEN" ]; then
  echo "Login failed - check the cert's CN matches oncall-kill-switch's allowed_common_names:" >&2
  echo "$LOGIN_RESPONSE" >&2
  exit 1
fi

echo "==> Soft-deleting ${SPACE}/${AGENT_NAME} (env=${ENVIRONMENT}) versions: $*"
curl -sS -X POST \
  -H "X-Vault-Token: ${TOKEN}" \
  -d "{\"versions\": ${VERSIONS_JSON}}" \
  "${URL}/v1/secret/delete/prompts/${ENVIRONMENT}/${SPACE}/${AGENT_NAME}"

echo
echo "==> Done. Attributed to this cert's registered identity in OpenBao's audit log."
echo "    Reinstatement (if ever needed) goes through the normal Keycloak-gated"
echo "    Admin UI path, two-person - not this script. See undelete in"
echo "    docs/design/openbao-api-reference.md §10."
