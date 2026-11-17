# Hospital onboarding (personas in KC, permissions in org DB)

## Model

| | Keycloak | Org DB |
|---|---|---|
| Personas (Doctor, Nurse, …) | **SoR** — client roles `persona-*` on `racc` | Mirror catalog + user.role_id |
| Permission matrix | — | **SoR** |
| User login identity | **SoR** (`sub`, realm) | `users.external_subject` |

Same persona pack for every hospital (`personas.json`).

## Steps

1. Copy env:

```bash
cp keycloak/hospital-onboarding/hospital.env.example hospital-meridian.env
# edit HOSPITAL_*, URIs, KC_*, ORG_DB_*
```

2. Onboard Keycloak realm:

```bash
chmod +x scripts/onboard-hospital.sh scripts/sync-kc-personas-to-orgdb.sh
./scripts/onboard-hospital.sh ./hospital-meridian.env
```

3. Hospital IT assigns users `persona-doctor`, etc. in Admin Console.

4. Sync to org DB (when DB is reachable):

```bash
./scripts/sync-kc-personas-to-orgdb.sh ./hospital-meridian.env
```

5. Maintain matrix cells only in org DB (Full/View/Edit/Assigned/None per module).

## Notes

- Stock KC 26 has no Realm Attributes UI — `loginLogoUrl` is set by the onboard script via Admin API.
- Adjust SQL in `sync-kc-personas-to-orgdb.sh` if your `roles`/`users` column names differ.
- Re-run onboard to refresh clients/theme/logo; re-run sync after persona assignment changes.
