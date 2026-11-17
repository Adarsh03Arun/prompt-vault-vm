# Keycloak ops notes (quirks & gotchas)

Living notes for this VM deploy. Prefer short, specific facts that are
easy to miss in stock Keycloak docs. Add new items when something is
**unique to our setup** or **surprising in KC 26**.

---

## 1. Topology (this project)

| Concept | Our meaning |
|---|---|
| Keycloak VM | `xel-openbao-keycloak-dev` (project `xel-dev-platform`) |
| Public check | `http://<EXTERNAL_IP>:8080/` |
| Internal hostname | `login.dev.xelerait.internal` — **does not resolve** from laptops without hosts/VPN |
| Compose home on VM | `~/keycloak` |
| Repo clone on VM | `~/tch` → [prompt-vault-vm](https://github.com/Adarsh03Arun/prompt-vault-vm) |
| Theme JAR | `vm/keycloak/providers/xelerait-keycloak-theme-26.jar` |
| Theme name | **`xelerait`** (login only) |
| Pilot realm | `tch` |

Hospital tenancy direction (product): **one realm per hospital**, apps as
clients inside that realm. Persona/permission matrix for RACC lives in
**Postgres**, not as Keycloak composite roles (see platform design doc).
Keycloak proves identity + hospital (realm); the app resolves persona.

---

## 2. Login theme (`xelerait`)

### Deploy / refresh JAR

```bash
cd ~/tch && git pull
mkdir -p ~/keycloak/providers
cp ~/tch/vm/keycloak/providers/xelerait-keycloak-theme-26.jar ~/keycloak/providers/
cp ~/tch/vm/keycloak/docker-compose.yml ~/keycloak/
cd ~/keycloak
docker compose up -d --force-recreate keycloak
docker exec xelerait-keycloak ls -la /opt/keycloak/providers
```

You **must** see the JAR inside the container. `docker compose restart`
alone is not enough if the volume/mount or file just appeared — use
**`--force-recreate`**.

Compose must include:

```yaml
volumes:
  - ./providers:/opt/keycloak/providers:ro
```

### Theme not in Login theme dropdown

Usually means:

1. JAR not under `~/keycloak/providers/`, or
2. providers volume not mounted, or
3. container not recreated after copying the JAR.

Hard-refresh Admin Console after recreate (Ctrl+Shift+R).

### Selecting the theme ≠ previewing it

**Realm settings → Themes** only *assigns* the theme. To *see* the branded
login UI, open a real login URL (incognito):

```
http://<EXTERNAL_IP>:8080/realms/tch/account/
```

Then Sign in — or use the OIDC auth URL for `account-console`.

### `loginTheme` in `realm-export.json`

`"loginTheme": "xelerait"` applies on **first realm import only**.
If the realm already exists, set Login theme in Admin UI (or PUT realm
via Admin API). Re-copying `realm-export.json` alone will not change an
existing realm’s theme.

### English only

Theme hides the language switcher. Keep realm localization to English
for now.

---

## 3. Hospital logo + XelerAIT logo (co-brand)

Intent: **same Keycloakify theme** on every hospital realm; show

`[hospital logo] | [XelerAIT logo]`

Branding is **realm-based**, not user-based. At the login screen Keycloak
only knows the **realm from the URL**, not which user will sign in. Do
not try to pick the logo from “user belongs to hospital X” before
credentials.

### Realm attribute `loginLogoUrl`

| Key | Value |
|---|---|
| `loginLogoUrl` | Public HTTPS URL to that hospital’s logo PNG/SVG |

Theme code (when rebuilt with the co-brand patch) reads
`kcContext.realm.attributes.loginLogoUrl`. XelerAIT logo is always shown.

### Gotcha: no “Attributes” under Realm settings in stock KC 26

Vanilla **Keycloak 26 Admin Console does not show a Realm attributes
tab**. (Some vendor admin themes, e.g. Phase Two, add one.)

**Do not confuse with:**

**Realm settings → User profile → Attributes**

That screen is for **user** fields (`username`, `email`, …). Creating an
attribute there will **not** drive the login logo.

### Set realm attributes via Admin API

```bash
TOKEN=$(curl -s -X POST "http://127.0.0.1:8080/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=YOUR_KC_ADMIN_USER" \
  -d "password=YOUR_KC_ADMIN_PASSWORD" \
  -d "grant_type=password" | jq -r .access_token)

REALM=tch   # or hospital-meridian, etc.

curl -s -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8080/admin/realms/${REALM}" > /tmp/realm.json

jq --arg url "https://YOUR-CDN/hospital-logo.png" \
  '.attributes.loginLogoUrl = $url' /tmp/realm.json > /tmp/realm2.json

curl -s -X PUT "http://127.0.0.1:8080/admin/realms/${REALM}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/realm2.json
```

### Fallback without attributes

Drop `img/hospitals/<realm-name>.png` into the theme resources (rebuild
JAR) named after the realm. Prefer `loginLogoUrl` when possible.

---

## 4. Permissions matrix vs Keycloak (RACC)

UI modules (Dashboard, Claims, Documents, …) with levels
Full / Edit / Assigned / View / None:

| Layer | Keycloak modeling |
|---|---|
| Module | Optional **composite** client role (packaging only) |
| Level | **Atomic** client roles, e.g. `claims:assigned`, `documents:edit` |
| No access | No role for that module |
| Assigned | Flag in token; **row filter** (dept/branch) enforced in app/DB |

Authorize APIs on **atomics**. One level per module (replace, don’t stack).
Current product decision: matrix may stay in **Postgres**; if moved into
Keycloak, use client roles on client `racc` as above — not realm roles.

---

## 5. Health checks

| Check | Expect |
|---|---|
| VM status | `xel-openbao-keycloak-dev` RUNNING |
| `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/realms/tch` | `200` |
| `docker exec xelerait-keycloak ls /opt/keycloak/providers` | theme JAR listed |
| OpenBao | `https://<IP>:8200/v1/sys/health` → initialized, unsealed |

Postgres for Keycloak is **loopback-only** (`127.0.0.1:5432`). Use SSH/IAP
local-forward for DBeaver; do not open 5432 publicly.

---

## 6. Changelog of “gotcha” discoveries

| Date | Note |
|---|---|
| 2026-11-17 | Theme JAR valid (`META-INF/keycloak-themes.json` → name `xelerait`) but invisible in UI until JAR mounted **inside** container + recreate |
| 2026-11-17 | Themes admin page does not preview login UI — need `/realms/<realm>/account` login flow |
| 2026-11-17 | `login.dev.xelerait.internal` does not resolve from laptop DNS |
| 2026-11-17 | Stock KC 26: no Realm attributes UI; User profile Attributes ≠ realm branding |
| 2026-11-17 | Co-brand = hospital `loginLogoUrl` + always-on XelerAIT logo; realm from URL, not from user |
| 2026-11-17 | `realm-export.json` `loginTheme` only on first import |

---

## 7. How to extend this doc

When you hit something odd:

1. Add a row to §6 with the date.
2. Add a short subsection under the relevant topic (§2–§5).
3. Keep “what we expected” vs “what KC actually did” in one or two lines.
