# Bound via auth/jwt to the "vault-admin" Keycloak client role.
#
# NOTE: deliberately does NOT grant secret/delete/prompts/* (the kill
# switch) or secret/destroy/prompts/* here. The kill switch's credential
# path is an open decision - see kill_switch/README.md. Even vault-admin
# goes through whichever path gets decided there, not through this policy.
# Reinstatement (undelete) IS included below, since that was already
# decided to stay on the normal Keycloak-gated, two-person path - it's not
# time-critical the way the kill itself is.
#
# Does NOT write prompt data — GitOps is the sole writer of new versions.
# custom_metadata (status / active_version) is the human-writable surface.

path "secret/data/prompts/*" {
  capabilities = ["read"]
}

path "secret/metadata/prompts/*" {
  capabilities = ["read", "list", "update"]
}

path "secret/undelete/prompts/*" {
  capabilities = ["update"]
}

path "sys/policies/acl/*" {
  capabilities = ["read", "list", "create", "update"]
}

# The wildcard above does NOT cover the bare collection path LIST needs -
# Vault/OpenBao's glob match requires the literal "sys/policies/acl/"
# prefix, which "sys/policies/acl" (no trailing slash) doesn't have.
# Confirmed by testing exactly this against a real server, 2026-10-27 -
# see vault-viewer.hcl's identical identity-overview block for the rest
# of what the Admin UI's "Access" screen needs.
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "identity/entity/id" {
  capabilities = ["list"]
}

path "identity/entity/id/*" {
  capabilities = ["read"]
}
