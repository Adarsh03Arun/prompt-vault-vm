#!/usr/bin/env bash
set -euo pipefail

# Registers one agent's identity with OpenBao so agent-prompt-read.hcl's
# {{identity.entity.metadata.space}} template has something to resolve.
# Agent-agnostic: takes the agent's identity as arguments, never hardcodes
# a roster - run this once per new agent, regardless of which space it's
# in or which auth method is active.
#
# Usage: register_agent_identity.sh <agent_name> <space> <common_name>
#
# Requires: bao CLI (authenticated), jq.

AGENT_NAME="${1:?usage: register_agent_identity.sh <agent_name> <space> <common_name>}"
SPACE="${2:?missing space}"
COMMON_NAME="${3:?missing common_name}"
AGENT_AUTH_METHOD="${AGENT_AUTH_METHOD:-cert}"

# Two different response shapes depending on whether this entity already
# existed - confirmed for real, 2026-10-27: creating a NEW entity returns
# its id in the response body (-field=id works), but writing the SAME
# name again (an update-in-place, which is what every re-run after the
# first does) returns an empty body, so -field=id silently captured the
# CLI's own "Success! ..." text instead of a real ID. Reading the entity
# back by name afterward is reliable either way.
bao write identity/entity name="agent-${AGENT_NAME}" metadata=space="${SPACE}" > /dev/null
entity_id="$(bao read -field=id "identity/entity/name/agent-${AGENT_NAME}")"

# Add this entity to its space's Identity Group (created per-space in
# bootstrap_openbao.sh) - purely organizational/browsable (resolved
# 2026-10-27), doesn't affect how access is decided. identity/group
# writes REPLACE the member list, not append to it (confirmed against a
# real server: writing only the new member ID silently dropped every
# existing one) - so this reads the current list first.
existing_members="$(bao read -format=json "identity/group/name/${SPACE}" 2>/dev/null | jq -r '.data.member_entity_ids[]?' || true)"
if [ -z "$existing_members" ]; then
  bao write identity/group name="${SPACE}" type=internal member_entity_ids="${entity_id}" > /dev/null
else
  all_members="$(printf '%s\n%s' "$existing_members" "$entity_id" | sort -u | paste -sd, -)"
  bao write "identity/group/name/${SPACE}" member_entity_ids="${all_members}" > /dev/null
fi

case "$AGENT_AUTH_METHOD" in
  cert)
    accessor="$(bao auth list -format=json | jq -r '.["cert/"].accessor')"
    bao write identity/entity-alias \
      name="${COMMON_NAME}" \
      canonical_id="${entity_id}" \
      mount_accessor="${accessor}"
    ;;
  spiffe)
    echo "SPIFFE agent auth not implemented yet - see openbao/auth/agent/spiffe/README.md" >&2
    exit 1
    ;;
  *)
    echo "Unknown AGENT_AUTH_METHOD '${AGENT_AUTH_METHOD}'" >&2
    exit 1
    ;;
esac

echo "Registered ${AGENT_NAME} (space=${SPACE}, cn=${COMMON_NAME}) as entity ${entity_id}"
