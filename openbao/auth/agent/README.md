# Agent-side auth method — configurable, cert implemented now

Status: **configurable, like the kill switch.** Controlled by the
`agent_auth_method` Terraform variable (mirrored at bootstrap time by the
`AGENT_AUTH_METHOD` env var) in `../../../terraform/variables.tf`.

- `"cert"` (**default, implemented**) — `auth/cert`, mTLS. See `cert/`.
- `"spiffe"` (**stubbed, not implemented**) — SPIFFE/SPIRE via `auth/jwt`
  against a trust domain instead of Keycloak. See `spiffe/README.md` — it's
  a placeholder so swapping to it later is a config change plus filling in
  that folder, not a redesign.

This was previously an open decision (cert vs. SPIFFE) with no scaffolding
either way. Per instruction on 2026-10-25, it's now implemented as a
configurable toggle, defaulting to cert, so work can start without the
SPIFFE question being settled first.

## How agent identities get their "space" metadata

Regardless of which method is active, `../policies/agent-prompt-read.hcl`
only works because each agent is also registered as an OpenBao **identity
entity** carrying `metadata.space = <space>`, with an **entity-alias**
linking that entity to whatever the auth method's login produced (the
cert's Common Name, for `cert`). This is a one-time identity-provisioning
step per agent — separate from, and not blocked by, the infra scaffolding
in this repo, which stays agent-agnostic (see `../../CONTEXT.md`).

Run `../../scripts/register_agent_identity.sh <agent_name> <space>
<common_name>` to do this for a new agent. The script itself is
agent-agnostic — it takes the agent's identity as arguments, it doesn't
hardcode a roster.

## To activate a different method

1. Change `agent_auth_method` in `terraform/variables.tf`.
2. Fill in the corresponding subfolder here if it's still a stub (`spiffe/`
   currently is).
3. Re-run `scripts/bootstrap_openbao.sh` with `AGENT_AUTH_METHOD` set to
   match.
4. Update `../../CONTEXT.md`'s decision log and add a `CHANGELOG.md` line.
