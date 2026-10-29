# The review/release capability tier - backs FOUR distinctly-named
# OpenBao policies, one per persona whose real capability is "read plus
# update custom_metadata" given decisions already locked in elsewhere
# (resolved 2026-10-27, see ../../CONTEXT.md): domain-reviewer,
# technical-reviewer, release-manager, space-owner. All four do the same
# thing at the OpenBao level - write a status/active_version change to
# custom_metadata - they differ in which Keycloak role maps to them and
# what the Admin UI's workflow calls the action (approve, reject, advance
# rollout, request deprecation), not in OpenBao capability. Kept as four
# names, not one, so the audit log shows which kind of persona acted.
# scripts/bootstrap_openbao.sh writes all four OpenBao policy names from
# this one file. Does NOT write prompt data — GitOps
# (gitops-pipeline-write.hcl) is the sole writer of new versions. No
# kill-switch capability here either - see kill_switch/README.md.

path "secret/data/prompts/*" {
  capabilities = ["read"]
}

path "secret/metadata/prompts/*" {
  capabilities = ["read", "list", "update"]
}

# Read-only access overview (Admin UI "Access" screen) - see
# vault-viewer.hcl's identical block for why this is in every role's
# policy. Verified against a real server 2026-10-27.
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "identity/entity/id" {
  capabilities = ["list"]
}

path "identity/entity/id/*" {
  capabilities = ["read"]
}
