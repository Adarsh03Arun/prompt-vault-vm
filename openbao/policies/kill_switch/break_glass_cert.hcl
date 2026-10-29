# Candidate A — NOT YET ACTIVATED. See README.md before wiring this up.
# Drafted so flipping kill_switch_auth_mode to "break_glass_cert" is a
# config change, not new design work.
#
# Intended binding: auth/cert role for a small on-call identity set, reached
# over a bastion/IAP tunnel - independent of Keycloak and the Admin UI.
#
# Deliberately spans ALL spaces (kiosk-pod, racc, shared) - see README.md.

path "secret/delete/prompts/*" {
  capabilities = ["update"]
}
