# OpenBao auth methods

Two independent paths, each configurable on its own axis, plus a GitOps
CI path that is not a persona/agent identity:

- **`human/`** — the Admin UI path. `auth/jwt` configured against Keycloak
  as OIDC provider. The auth *method* is decided (JWT vs Keycloak); the
  *realm topology* is configurable (`KEYCLOAK_REALM_TOPOLOGY`, default
  `shared`) — see `../../keycloak/README.md`.
- **`agent/`** — the agent-workload path. Configurable via the
  `AGENT_AUTH_METHOD` env var consumed by `../../scripts/bootstrap_openbao.sh`
  (default: `cert`, implemented now). See `agent/README.md` for the toggle
  and why `spiffe` is stubbed but not wired up yet.
- **`gitops/`** — GitHub Actions OIDC on a second JWT mount
  (`auth/jwt-github`). Mints a one-time `gitops-pipeline` AppRole
  secret_id per CI run; cannot write prompts itself. See `gitops/README.md`.

The human and agent paths feed the same space-agnostic policy
(`../policies/agent-prompt-read.hcl`) via identity entity metadata — see
`agent/README.md` for how that metadata gets attached per auth method.
