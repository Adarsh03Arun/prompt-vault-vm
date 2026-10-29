# Keycloak VM Setup

This is a quick, single-VM setup to get something real running now. A
more resilient, multi-server cloud version exists for later, once this
is depended on by more than just our one project — not needed yet.

## 1. Pick the address first

Decide the internal web address this will be reachable at (e.g.
`keycloak.internal.yourcompany.com`) **before turning it on**, not
after. Keycloak stamps that address into every login token it issues —
if people reach it under different addresses from different places,
logins start failing with a confusing error. We hit this exact problem
while testing and had to fix it by locking the address in up front.
Pick one address, use it everywhere, and don't change it later without
telling us (changing it breaks every login token issued under the old one).

## 2. What's needed before this can run

- A server (VM) with Docker installed
- That server needs to be reachable by: people logging in through a
  browser, our admin tool's backend, and later our vault system
  (OpenBao) checking logins
- That server needs outbound network access to the existing Postgres
  database server
- On that Postgres server: a database (e.g. `keycloak`) and a login
  account that **owns** it — meaning it can create tables, not just
  read/write existing ones. Keycloak builds its entire internal
  database structure itself the first time it starts (confirmed in our
  testing — it created ~90 tables automatically). If the account can't
  create tables, that first startup fails partway through. Whoever
  manages the Postgres server should create this database + account —
  this setup only connects to it, it doesn't create it.
- A security certificate (TLS/HTTPS) for that address, or a decision to
  put this behind a proxy/load balancer that handles that — this setup
  runs over plain HTTP and assumes something in front of it secures the
  connection for real use

## 3. What happens the first time it starts

Confirmed directly in our own testing: the moment Keycloak connects to
an empty database, it builds its entire internal database structure by
itself — no setup scripts to run, nothing for IT to prepare manually
beyond the empty database and account above.

A few practical things worth knowing:

- It checks and does this on **every** restart, but it remembers what
  it already did, so a normal restart doesn't redo any of it or cause
  problems.
- It does this **again** every time the software version is upgraded
  later — an upgrade applies whatever's new since the last version. This
  is why the database account needs those table-creation rights
  permanently, not just for the very first setup.
- It only ever touches the one database it's told to use — nothing else
  on that shared Postgres server.

## 4. The setup itself (docker-compose.yml)

```yaml
services:
  keycloak:
    image: quay.io/keycloak/keycloak:26.0
    restart: unless-stopped
    command: start --http-enabled=true
    environment:
      # Change this password after first login - don't leave it in a
      # file that gets checked into any shared/version-controlled location.
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KC_ADMIN_PASSWORD:?set KC_ADMIN_PASSWORD in .env}
      # The existing Postgres server - must already have the database
      # and account described in §2.
      KC_DB: postgres
      KC_DB_URL_HOST: ${POSTGRES_HOST:?set POSTGRES_HOST in .env}
      KC_DB_URL_PORT: ${POSTGRES_PORT:-5432}
      KC_DB_URL_DATABASE: ${POSTGRES_DB:-keycloak}
      KC_DB_USERNAME: ${POSTGRES_USER:?set POSTGRES_USER in .env}
      KC_DB_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
      # The address decided in §1 - must be set, must never silently change.
      KC_HOSTNAME: ${KC_HOSTNAME:?set KC_HOSTNAME in .env}
      KC_HOSTNAME_STRICT: "false"
    ports:
      - "8080:8080"
```

Put the real passwords and address in a separate `.env` file next to
this one (keep it out of anything shared/version-controlled):

```
KC_ADMIN_PASSWORD=<pick a real password>
POSTGRES_HOST=<existing Postgres server's address>
POSTGRES_PORT=5432
POSTGRES_DB=keycloak
POSTGRES_USER=<the account created for this>
POSTGRES_PASSWORD=<its password>
KC_HOSTNAME=keycloak.internal.yourcompany.com
```

Then run:

```
docker compose up -d
docker compose logs -f keycloak
```

First startup is slower than a restart (it's building things) — give it
1-2 minutes before assuming something's wrong.

**Check it worked:**

```
curl http://<address>:8080/realms/master/.well-known/openid-configuration
```

A response with some JSON containing `"issuer"` means it's up and the
address setting took effect. The admin login page is at
`http://<address>:8080/admin/`.

**Deliberately not handled by this setup**: HTTPS/TLS itself, running
more than one server for redundancy, and backups for the Postgres data
(that's already whoever manages that Postgres server's job). This gets
a real, working login server up — it's not the final hardened version.

## 5. What we need back from you once this is running

We don't need access to the server itself, just to the login system
running on it. There are two ways to do the next step — **pick one**:

**Option A — give our team admin access to the login system itself.**
We log in and configure everything ourselves (the application entry,
the permission levels, and two small internal settings that make the
tokens work correctly with our backend). We already have this process
built and tested. You'd give us: the web address, and an admin login
(either the one above, or a separate admin account you create just for
us).

**Option B — your team configures it, following a short spec we give you.**
You (or whoever manages company-wide logins) set up the application
entry and permission levels yourselves, using exact settings we'll
specify (an application name, three permission-level names, and two
small internal settings). You then hand us back just the connection
details — not admin access to the system. We'll tell you the one piece
we're responsible for (where logins should redirect back to) before you
create it.

## 6. Steps to configure it (Option B — or just to see what Option A does on your system)

Done through Keycloak's own admin web console, no outside tools needed.
Menu wording can shift slightly between versions — if a label doesn't
match exactly, look for the nearest equivalent; the *values* below are
what matter and are exactly what we tested working.

1. **Log in.** Go to `http://<address>:8080/admin/`, sign in with the
   admin account from §4.

2. **Create the realm** (a realm is an isolated space of users/apps —
   normally one per organization). Top-left realm dropdown → *Create
   realm*. Name it `tch` (the org namespace; prod Keycloak layout is
   still open — just tell us if you used a different realm name). Leave
   it enabled. Create.

3. **Do not create a Prompt Vault Admin UI client yet.** That app is
   still undecided. Other TCH services will add their own clients in
   this realm when they are ready.

4. **Send us back:**
   - The realm name you used (`tch` if you kept the suggestion)
   - The address from §1

Also tell us: whether the security certificate in front of
this (if any) is from an internal/private certificate authority rather
than a public one (if so, we need that certificate so our systems trust
it), and confirm the address from §1 is final before anyone builds
against it.
