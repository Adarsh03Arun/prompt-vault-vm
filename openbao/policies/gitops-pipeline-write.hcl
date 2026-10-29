# The CI pipeline's identity (bound to this policy via AppRole - see
# scripts/bootstrap_openbao.sh) - the sole writer of new prompt versions,
# per docs/design/openbao-architecture-and-integration.md §3.8 (GitOps
# versioning: GitHub is the source of truth for content/history, CI is the
# sole writer into the vault).
#
# Write-only by design: the pipeline can create new versions and PATCH
# content-descriptive custom_metadata (space, agent_name, owning_team,
# risk_tier, version, model) but cannot read existing ones back, list the
# catalogue, or touch the kill switch. PATCH merges those keys and must
# not send status / active_version — those stay a human-approval action.
# Signing uses the vault's own key (transit/sign/vault-signing) so approved
# content is signed on write - see FR-10 in the technical design doc.

path "secret/data/prompts/*" {
  capabilities = ["create", "update"]
}

path "secret/metadata/prompts/*" {
  capabilities = ["patch"]
}

path "transit/sign/vault-signing" {
  capabilities = ["create", "update"]
}
