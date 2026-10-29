# Candidate B — NOT YET ACTIVATED. See README.md before wiring this up.
# Identical capability to break_glass_cert.hcl; the only difference is which
# auth method/role binding this attaches to - auth/jwt + a Keycloak
# vault-admin/vault-approver claim, instead of auth/cert + an
# on-call-only identity.
#
# Deliberately spans ALL spaces (kiosk-pod, racc, shared) - see README.md.

path "secret/delete/prompts/*" {
  capabilities = ["update"]
}
