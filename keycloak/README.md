# Keycloak realm/client scaffolding

Status: **configurable, like agent auth.** Controlled by Terraform
variables in `../terraform/variables.tf`, mirrored at bootstrap time by
env vars consumed by `../scripts/bootstrap_keycloak.sh` and
`../scripts/bootstrap_openbao.sh`.

## Recommendation (the default)

**One shared org-wide realm, one dedicated client per backend.** Keycloak
is shared IAM, not this workstream's private IdP — a dedicated realm per
backend would fragment login, user directories, and SSO for no gain on
the Prompt Vault side. Client-level roles keep `vault-admin` /
`vault-approver` / `vault-viewer` from colliding with another backend's
roles in the same realm.

The shared realm name is **`tch`** (org namespace). Prod Keycloak
hosting is still open. The Prompt Vault Admin UI client is **not** in
`realm-export.json` yet — add it later if that UI is needed. Other TCH
services add their own clients in this same realm.

Defaults:

| Variable | Default |
|---|---|
| `keycloak_realm_topology` | `shared` |
| `keycloak_realm_name` | `tch` |
| `keycloak_client_id` | `prompt-vault-admin-ui` |
| `keycloak_role_source` | `client` (flattened into a top-level `vault_roles` claim - see below) |

`realm-export.json` is the `tch` realm skeleton (no Admin UI client).
Bootstrap creates that realm if missing. If a client is later added to
the export, bootstrap upserts **only** that client and its roles. In
`shared` topology it will not modify other clients, and will not rewrite
realm-level settings if the realm already exists.

**Two protocol mappers, not just role config — confirmed necessary
against a real Keycloak+OpenBao pair on 2026-10-25, not assumed:**
OpenBao's `bound_claims` matches a literal top-level claim key; it does
**not** traverse dot-paths into nested objects. Binding directly against
`resource_access.<client_id>.roles` or `realm_access.roles` (both nested)
looks plausible but fails with `"claim is missing"` the moment a real
token is presented. `scripts/bootstrap_keycloak.sh` now adds:
- a **flat `vault_roles` claim** — a `oidc-usermodel-client-role-mapper`
  (client-role source) or `oidc-usermodel-realm-role-mapper` (realm-role
  source) protocol mapper, so OpenBao's `bound_claims` can match a real
  top-level key (`openbao/auth/human/role-template.json.tmpl` binds
  `{"vault_roles": "<role>"}`).
- an **audience mapper** — Keycloak does not include a client in its own
  token's `aud` claim by default; without this, `bound_audiences:
  ["prompt-vault-admin-ui"]` would never match either.

The flat-claim fix above was verified end-to-end against a real server
(real token → real `auth/jwt/login` → correct policy). The audience
mapper was added for the same documented reason but wasn't independently
re-verified after being added — the real-server pass that succeeded used
`bound_audiences: ["account"]` (Keycloak's default audience) as a
stand-in while isolating the claim-flattening fix. Re-verify the audience
mapper specifically before relying on it in production.

## The other direction (dedicated realm)

If other backend owners on the shared Keycloak VM push back, or this
workstream needs isolation that client roles cannot give:

1. Set `keycloak_realm_topology = "dedicated"`.
2. Set `keycloak_realm_name` to a workstream-specific realm (suggested:
   `prompt-vault`). The topology flag does **not** rename the realm for
   you — that is deliberate, so an accidental flip cannot retarget the
   shared org realm.
3. Optionally set `keycloak_role_source = "realm"` so OpenBao
   `bound_claims` inspect `realm_access.roles`. Leave it at `client` if
   you still want the roles namespaced on the client.
4. Re-run `scripts/bootstrap_keycloak.sh` and `scripts/bootstrap_openbao.sh`
   with the matching env vars (`KEYCLOAK_REALM_TOPOLOGY`,
   `KEYCLOAK_REALM_NAME`, `KEYCLOAK_CLIENT_ID`, `KEYCLOAK_ROLE_SOURCE`,
   plus `KEYCLOAK_OIDC_HOST` for the JWT issuer URL).
5. Point the Admin UI's `KEYCLOAK_ISSUER` at
   `https://<host>/realms/<keycloak_realm_name>`.

Shared topology + `keycloak_role_source = "realm"` is rejected by a
Terraform check and warned about in bootstrap — realm roles in a shared
realm collide with every other backend.

## What bootstrap will not do

- It does not store the client secret. Set that in the Admin UI backend
  (`KEYCLOAK_CLIENT_SECRET`) out of band.
- It does not import a full realm (users, identity providers, other
  clients). `shared` must not clobber those; `dedicated` still starts
  from a thin realm (`enabled` / `sslRequired`) plus this client.
- It has not been run against a real Keycloak server.
