# auth/cert — agent-side mTLS (default, implemented)

`role-template.json.tmpl` documents the shape of the single
`auth/cert/certs/agent-cert-auth` role. `../../../../scripts/bootstrap_openbao.sh`
builds the equivalent payload via `jq` rather than substituting this file
directly (a CA PEM is multi-line, which plain `sed` substitution handles
badly inside JSON) - the fields are the same:

- The CA PEM comes from the file at `$AGENT_CA_CERT_PATH` (an env var
  pointing at your org's actual CA — **not committed to this repo**, same
  treatment as the TLS material TODO in `../../config.hcl.tmpl`).
- `allowed_common_names` comes from `$AGENT_ALLOWED_COMMON_NAMES` (default
  `*.agents.internal` if unset).

One role for every agent, regardless of space or identity — scoping to a
space happens entirely through the entity/entity-alias metadata set by
`register_agent_identity.sh`, not through separate per-agent cert roles.
This keeps the cert-auth config itself agent-agnostic: issuing a new agent
a certificate under the trusted CA is enough to let it authenticate: it
still needs an entity registered before any `secret/data/prompts/...` read
will succeed, which is the one per-agent step that can't be eliminated
(an identity has to exist somewhere).

Not yet implemented here: CA issuance/rotation process itself, and
short-lived cert issuance for agents (today this assumes a long-lived cert
per agent signed by a CA you already operate elsewhere).
