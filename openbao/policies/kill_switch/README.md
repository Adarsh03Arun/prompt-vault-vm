# Kill-switch auth path — resolved: break-glass cert

Status: **resolved (2026-10-25) as `break_glass_cert`.** Fully wired:
`terraform/variables.tf`'s `kill_switch_auth_mode` now defaults to
`"break_glass_cert"`, `scripts/bootstrap_openbao.sh` provisions the
`oncall-kill-switch` auth/cert role on its own CA, and
`scripts/register_oncall_identity.sh` / `scripts/oncall_kill_switch.sh` are
the operational pair for registering an on-call engineer and actually
pulling the switch.

**Why this one, not `keycloak_gated`**: `../../CONTEXT.md`'s "Decisions
already locked in" already commits to the kill switch needing a short,
Keycloak-independent dependency chain *before* this decision was made —
`keycloak_gated` would violate that by construction (an emergency control
riding on the same IAM that might be the thing that's down). Once that
principle was locked in, `break_glass_cert` was the only option left
consistent with it, which is why resolving #1 didn't require picking
between two live options so much as recognizing the earlier decision had
already narrowed it.

`keycloak_gated.hcl` stays in this folder as a documented, not-recommended
alternative (same pattern as SPIFFE being kept as a documented alternative
to cert for agent auth) — switch to it only if the Keycloak-independence
requirement itself gets revisited.

## The two candidates already drafted here

- **`break_glass_cert.hcl`** — a narrow policy (capability: `update` on
  `secret/delete/prompts/*` only, spanning all spaces) bound to a small set
  of on-call cert identities via `auth/cert`, reached over a bastion/IAP
  tunnel. Independent of Keycloak and the Admin UI — survives either being
  down, which matters because the kill switch is itself an incident-response
  tool.
- **`keycloak_gated.hcl`** — identical capability, but bound via `auth/jwt`
  to the `vault-admin`/`vault-approver` Keycloak client roles, i.e. rides
  the normal Admin UI login path.

Both grant the same capability on purpose — the only difference between
them is which auth method/role binding they attach to. That's what makes
flipping between them later a config change, not new policy design.

## Why this isn't decided yet

Break-glass has a shorter dependency chain (good for an emergency control,
since it works even if Keycloak — now shared org-wide IAM — or the Admin UI
backend is down) but is a second credential type to issue, rotate, and
audit. Keycloak-gated reuses existing IAM machinery but inherits Keycloak's
own availability, which matters more now that Keycloak serves other
backends too. See the full tradeoff in
`docs/design/prompt-vault-technical-design-keycloak-openbao.md` and the
kill-switch discussion logged in `../../CONTEXT.md`.

Both candidates deliberately span **all three spaces** (kiosk-pod, racc,
shared) — an explicit, documented exception to the normal per-space scoping
every other agent/persona policy gets. An incident can hit any agent;
on-call shouldn't have to request space-specific access mid-incident. This
part of the design is NOT open — only the auth-method choice is.

## How it's wired now (break_glass_cert)

1. `scripts/bootstrap_openbao.sh`, mode `break_glass_cert`: writes the
   `oncall-kill-switch` policy, enables `auth/cert` if not already (the
   agent-cert path may have done so already — idempotent either way), and
   registers a **separate** cert role `auth/cert/certs/oncall-kill-switch`
   on its own CA (`ONCALL_CA_CERT_PATH`, distinct from
   `AGENT_CA_CERT_PATH` — on-call humans are a different trust domain than
   agent workloads), with short-lived tokens (5min/15min TTL — an
   emergency credential, not a standing service identity).
2. `scripts/register_oncall_identity.sh <handle> <common_name>` — run once
   per on-call engineer, purely for audit attribution (the policy grant
   itself comes from the cert role match, not this step — see the
   script's own comment for why it's still worth doing).
3. `scripts/oncall_kill_switch.sh <url> <cert> <key> <env> <space> <agent> <versions...>`
   — the actual break-glass action: logs in via `auth/cert` over mTLS,
   soft-deletes the given versions. No Keycloak, no Admin UI, no browser
   anywhere in this chain.

**One known follow-on, not yet done**: the Admin UI's kill-switch screen
still POSTs through `admin/backend/`'s Keycloak-gated session, which will
now always 403 against a real server — no Keycloak-authenticated identity
carries the `oncall-kill-switch` policy, by design. The UI should probably
show "use the break-glass runbook" messaging instead of attempting a
doomed API call; not fixed yet (tracked in `../../CONTEXT.md`).

## Switching to keycloak_gated instead

1. Set `kill_switch_auth_mode = "keycloak_gated"` in `terraform/variables.tf`.
2. In `scripts/bootstrap_openbao.sh`'s `keycloak_gated` case: attach the
   `oncall-kill-switch` policy to the relevant `auth/jwt` role's
   `token_policies` in `../auth/human/`.
3. Update `../../CONTEXT.md`'s decision #1 entry and add a `../../CHANGELOG.md` line.
