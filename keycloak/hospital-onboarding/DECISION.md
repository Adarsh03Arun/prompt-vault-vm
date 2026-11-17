# Decision: personas in Keycloak, permissions in org DB

**Status:** chosen 2026-11-17  
**Supersedes (for hospital product):** “Keycloak identity-only; personas in Postgres” in the older platform design draft — that remains true for Prompt Vault shared `tch` realm; **hospital realms** use this model instead.

## Split

| Concern | System of record | Notes |
|---|---|---|
| Persona (Doctor, Nurse, Lab, …) | **Keycloak** | Client roles on `racc` (and later `pod`). Hospital IT assigns in Admin Console. |
| Permission matrix (Claims:view, …) | **Org DB** | Same matrix template every hospital; keyed by `persona_key`. |
| User identity (`sub`) + hospital | **Keycloak** | Realm = hospital. |
| User row + `external_subject` | **Org DB** | Mirror of KC user; sync keeps them aligned. |

## Same every hospital

- Persona role pack (see `personas.json`)
- Clients: `racc`, `pod` (pod may start disabled)
- Login theme: `xelerait`
- Permission matrix template in org DB (seed SQL / JSON)

## Different per hospital (`.env`)

- Realm name / display name
- `loginLogoUrl`
- Redirect URIs / web origins
- `hospital_id` in org DB

## Sync

- **KC → Org DB (primary):** persona assignment + user link (`sub` → `external_subject`)
- **Org DB:** only place permission cells are edited
- Prefer **one writer** for persona: Keycloak. Org DB mirrors; app does not invent personas that don’t exist in KC.

## Onboard

```bash
cp keycloak/hospital-onboarding/hospital.env.example hospital-meridian.env
# edit …
./scripts/onboard-hospital.sh hospital-meridian.env
./scripts/sync-kc-personas-to-orgdb.sh hospital-meridian.env   # when org DB reachable
```
