# auth/jwt via SPIFFE/SPIRE — stub, not implemented

Placeholder only, kept parallel to `../cert/` so switching
`agent_auth_method` to `"spiffe"` later is a matter of filling this folder
in, not redesigning the toggle itself.

Intended shape when implemented: `auth/jwt` configured with a SPIRE
trust-domain bundle as the issuer (instead of Keycloak's discovery URL, the
way the human path uses it), validating SPIFFE IDs
(`spiffe://<trust-domain>/<space>/<agent>` or similar) and mapping them to
`agent-prompt-read` + the same entity/entity-alias metadata pattern used by
the cert path.

Not drafted yet because `bootstrap_openbao.sh` currently exits with "not
implemented" if `AGENT_AUTH_METHOD=spiffe` is set — see
`../README.md` and `../../../../scripts/bootstrap_openbao.sh`.
