#!/usr/bin/env bash
set -euo pipefail

# Registers one on-call engineer's identity with OpenBao, purely for audit
# attribution. The oncall-kill-switch auth/cert role (see
# scripts/bootstrap_openbao.sh) already grants the oncall-kill-switch
# policy to any cert matching its allowed_common_names - that part doesn't
# need an entity/alias to work. Without one, though, a break-glass action
# is still logged but only under an anonymous cert-matched token, not a
# named person. Run this once per on-call engineer so "who pulled the kill
# switch" is unambiguous in the audit log - the whole point of a
# break-glass path is that it must stay fully attributable even though
# it's independent of Keycloak.
#
# Usage: register_oncall_identity.sh <engineer_handle> <common_name>
#
# Requires: bao CLI (authenticated), jq.

HANDLE="${1:?usage: register_oncall_identity.sh <engineer_handle> <common_name>}"
COMMON_NAME="${2:?missing common_name}"

entity_id="$(bao write -field=id identity/entity name="oncall-${HANDLE}")"
accessor="$(bao auth list -format=json | jq -r '.["cert/"].accessor')"
bao write identity/entity-alias \
  name="${COMMON_NAME}" \
  canonical_id="${entity_id}" \
  mount_accessor="${accessor}"

echo "Registered on-call engineer ${HANDLE} (cn=${COMMON_NAME}) as entity ${entity_id}"
