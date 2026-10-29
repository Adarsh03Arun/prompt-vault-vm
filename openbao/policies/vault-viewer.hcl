# The read-only capability tier - backs THREE distinctly-named OpenBao
# policies (not just "vault-viewer"), one per persona whose real
# capability is read-only given decisions already locked in elsewhere
# (resolved 2026-10-27, see ../../CONTEXT.md):
#   - prompt-author     - drafting happens via a PR to the prompts/ repo,
#                          not this UI; GitOps is the sole writer, so
#                          there is no real "write" capability to grant
#   - security-officer   - the kill switch is a break-glass certificate
#                          (scripts/register_oncall_identity.sh),
#                          deliberately independent of Keycloak - no
#                          Keycloak role ever carries that capability
#   - auditor            - read-only by definition
# scripts/bootstrap_openbao.sh writes all three OpenBao policy names from
# this one file, each bound to its own Keycloak client role - so the
# audit log shows which kind of persona acted, not a generic label, while
# the actual capability content (and any future change to it) lives in
# exactly one place.
#
# Catalogue browsing + version history, no writes, no kill switch.

path "secret/data/prompts/*" {
  capabilities = ["read"]
}

path "secret/metadata/prompts/*" {
  capabilities = ["read", "list"]
}

# Read-only access overview (Admin UI "Access" screen) - who exists
# (agent/on-call identities) and what policies exist. Granted to every
# role, not just vault-admin: viewing this needs no write capability.
# Verified against a real server: these three paths, exactly as written,
# 2026-10-27.
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "identity/entity/id" {
  capabilities = ["list"]
}

path "identity/entity/id/*" {
  capabilities = ["read"]
}
