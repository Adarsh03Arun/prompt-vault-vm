# Agent-agnostic by construction: this is the ONE policy bound to every
# agent identity, regardless of which agent or which space it belongs to.
# Scoping comes entirely from the authenticated identity's own "space"
# metadata, set at auth-method role-binding time (cert subject field /
# SPIFFE ID - decision B-vs-C still open, see ../../CONTEXT.md #2).
#
# A new agent landing in an existing space needs ZERO changes to this file.
# A new space needs one line in ../../spaces.yaml plus a role binding -
# never a new policy.
#
# Path shape matches docs/design/openbao-architecture-and-integration.md
# §3.2: secret/data/prompts/<env>/<space>/<agent_name>. The leading "+"
# below is the <env> segment.

path "secret/data/prompts/+/{{identity.entity.metadata.space}}/*" {
  capabilities = ["read"]
}

path "secret/metadata/prompts/+/{{identity.entity.metadata.space}}/*" {
  capabilities = ["read", "list"]
}
