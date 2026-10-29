# OpenBao VM Setup — for IT/Infra Team

This sets up **OpenBao** — a secure storage system that holds the
configuration our AI agents run on, and tightly controls which system
is allowed to read or change which piece of it. It's a separate server
from the Keycloak login system.

Unlike Keycloak, this **does not need an external database** — it
manages its own storage internally. It does need a persistent disk,
though (see §2).

Once this is reachable, our team (Guardrails/Security) does the one-time
setup and all ongoing configuration remotely — not something IT needs to
do (see §5).

## 1. What's needed before this can run

- A server (VM) with Docker installed
- Reachable by: our AI agents (reading their configuration), our
  automated publishing process (writing updates to it), and our admin
  tool's backend (for human logins) — all need a network path to this
  server
- A real security certificate (TLS) for this server's address — **this
  one is not optional and cannot be handled by a separate proxy in
  front of this server**, unlike a typical web app. Some of our systems
  log in using a client certificate, and that check has to happen on a
  direct, secure connection to this exact server — a proxy terminating
  the connection on this server's behalf would break that. If you
  already have an internal certificate authority, a certificate from
  that works fine — just tell us so our systems trust it too (§6).

## 2. Persistent storage (no database — just a disk)

This system stores everything on its own, without a separate database
server. What it needs instead is a disk that **survives restarts** — if
that storage is wiped, everything stored is gone, permanently (there's
no copy anywhere else by default). Make sure whatever storage this is
pointed at isn't the kind that resets when the container restarts.

## 3. Unsealing — a manual step, by design

This system encrypts everything it stores behind a master key. Every
time it starts, **someone has to unlock it** by supplying pieces of that
key before it can be used for anything.

We're doing this manually for now rather than using a cloud provider's
automatic-unlock feature — deliberately, to avoid tying this system to
one specific cloud provider (consistent with the "minimal cloud
dependence beyond VMs" direction already agreed). The practical effect:
after this server restarts for any reason, there's a short manual step
before it's usable again. We (not IT) will own doing that step — see §5.

## 4. The setup itself

**Use `../vm/`**. Keycloak is `vm/keycloak/run.sh` (destination
`~/keycloak`). OpenBao + unsealer are `vm/openbao/run.sh` (destination
`~/openbao`). Same VM, two folders. Not the laptop `../docker/` stack.

If you are wiring a single OpenBao container by hand instead, create a
folder with this layout next to a `docker-compose.yml`:

```
./config/config.hcl
./certs/server.crt
./certs/server.key
```

`config/config.hcl`:

```hcl
storage "raft" {
  path    = "/openbao/data"
  node_id = "node1"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/openbao/certs/server.crt"
  tls_key_file  = "/openbao/certs/server.key"
}

api_addr     = "https://<this-server's-address>:8200"
cluster_addr = "https://<this-server's-address>:8201"
```

Replace `<this-server's-address>` with the real reachable address, and
put your real certificate + key in `certs/`.

`docker-compose.yml`:

```yaml
services:
  openbao:
    image: openbao/openbao:2.4
    restart: unless-stopped
    cap_add:
      - IPC_LOCK
    command: server -config=/openbao/config/config.hcl
    volumes:
      - openbao-data:/openbao/data
      - ./config:/openbao/config:ro
      - ./certs:/openbao/certs:ro
    ports:
      - "8200:8200"

volumes:
  openbao-data:
```

(`IPC_LOCK` lets it lock secrets in memory so they're never written to
disk swap — a real security measure, not boilerplate.)

Run it:

```
docker compose up -d
docker compose logs -f openbao
```

**Check it worked** (confirmed working the same way in our own testing):

```
curl -k https://<address>:8200/v1/sys/health
```

A JSON response (even showing `"sealed": true`) means it's up. `sealed:
true` is expected and correct at this point — that's §3, waiting on us.

## 5. What happens next (on our side, not yours)

Once it's reachable, we remotely run the one-time setup that generates
this system's master key and its first access credential — those get
generated fresh on our end and never need to pass through IT at all.
After that, we handle unsealing (§3) ourselves going forward.

## 6. What we need back from you

- The address from §1
- Confirmation the disk/volume backing this is persistent (§2)
- If the certificate is from an internal/private certificate authority
  rather than a public one: that CA's certificate, so our systems trust
  this server
