#!/usr/bin/env bash
set -euo pipefail

# Grants a Keycloak user an ELEVATED prompt-vault-admin-ui client role, on
# top of the auditor every user already has via the tch-users default
# group (see ../keycloak/realm-export.json's defaultGroups) - for testing
# any of the other 7 real personas (resolved 2026-10-27, see
# ../CONTEXT.md) locally without building an admin-approval UI for
# something that's a one-off dev need.
#
# This does NOT remove auditor first - it can't. auditor comes from group
# membership, not a direct role grant, so there is nothing on the user to
# remove (confirmed by actually trying this against vault-viewer, the
# predecessor of today's auditor role, 2026-10-27: a remove-then-add
# sequence left both roles present). That turns out not to matter:
# OpenBao's role selection (admin/backend/src/openbao.ts's
# selectOpenBaoLoginRole) always picks the highest-privilege role
# present, so a user holding both auditor and vault-admin still logs in
# as vault-admin. Re-running this with a different role is still
# idempotent for the elevated role itself (add-roles is a no-op if
# already granted).
#
# Usage: set_keycloak_user_role.sh <username> <role>
#   <role>  prompt-author | domain-reviewer | technical-reviewer |
#           release-manager | space-owner | vault-admin | security-officer
#
# Requires: kcadm.sh on PATH, authenticated against the target Keycloak
# server (kcadm.sh config credentials ...) before running this.
#
# Env vars:
#   KEYCLOAK_REALM_NAME   default: tch
#   KEYCLOAK_CLIENT_ID    default: prompt-vault-admin-ui

USERNAME="${1:?usage: set_keycloak_user_role.sh <username> <role>}"
ROLE="${2:?missing role}"
REALM="${KEYCLOAK_REALM_NAME:-tch}"
CLIENT_ID="${KEYCLOAK_CLIENT_ID:-prompt-vault-admin-ui}"

case "$ROLE" in
  prompt-author|domain-reviewer|technical-reviewer|release-manager|space-owner|vault-admin|security-officer) ;;
  auditor) echo "Every user already has auditor via the tch-users default group - nothing to do." >&2; exit 0 ;;
  *) echo "Unknown role '$ROLE' - must be one of: prompt-author, domain-reviewer, technical-reviewer, release-manager, space-owner, vault-admin, security-officer." >&2; exit 1 ;;
esac

kcadm.sh add-roles -r "$REALM" --uusername "$USERNAME" --cclientid "$CLIENT_ID" --rolename "$ROLE"

echo "Granted ${USERNAME} the ${ROLE} role on ${CLIENT_ID} (in addition to the default auditor)."
