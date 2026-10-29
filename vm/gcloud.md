# Deploy on the VM — from login

Project: `xel-dev-platform`

Replace `VM_NAME` and `ZONE` from `instances list`. Same VM, three home dirs:

| Path | What |
|---|---|
| `~/keycloak` | Keycloak + Postgres (shared IAM) |
| `~/openbao` | OpenBao + unsealer (prompt vault) |
| `~/tch` | bootstrap scripts, policies, `spaces.yaml` |

`KEYCLOAK_ADMIN_*` is the **master** console admin, not a `tch` app user.

## 1. Laptop — log in

```
gcloud auth login
gcloud config set project xel-dev-platform
gcloud compute instances list --project xel-dev-platform
```

```
gcloud compute ssh VM_NAME --zone ZONE --tunnel-through-iap --project xel-dev-platform
```

## 2. Laptop — copy (PowerShell)

Windows `gcloud compute scp` uses PSCP, which does **not** expand `~`.
Create dirs over SSH (`~` works there), then scp to a path relative to
remote home (no `~`, no `/home/...`). Type `y` if asked to store the host key.

```
gcloud compute ssh VM_NAME --zone ZONE --tunnel-through-iap --project xel-dev-platform --command "mkdir -p ~/keycloak ~/openbao/scripts ~/tch"
```

Keycloak:

```
gcloud compute scp --recurse --tunnel-through-iap --zone ZONE --project xel-dev-platform ^
  C:\Coding\XelerAIT\Agents\tch\enterprise_agent_platform\deploy\identity-vault\vm\keycloak\* ^
  VM_NAME:keycloak/

gcloud compute scp --tunnel-through-iap --zone ZONE --project xel-dev-platform ^
  C:\Coding\XelerAIT\Agents\tch\enterprise_agent_platform\deploy\identity-vault\keycloak\realm-export.json ^
  VM_NAME:keycloak/realm-export.json
```

OpenBao + unsealer:

```
gcloud compute scp --recurse --tunnel-through-iap --zone ZONE --project xel-dev-platform ^
  C:\Coding\XelerAIT\Agents\tch\enterprise_agent_platform\deploy\identity-vault\vm\openbao\* ^
  VM_NAME:openbao/

gcloud compute scp --recurse --tunnel-through-iap --zone ZONE --project xel-dev-platform ^
  C:\Coding\XelerAIT\Agents\tch\enterprise_agent_platform\deploy\identity-vault\scripts\* ^
  VM_NAME:openbao/scripts/
```

Bootstrap tree:

```
gcloud compute scp --recurse --tunnel-through-iap --zone ZONE --project xel-dev-platform ^
  C:\Coding\XelerAIT\Agents\tch\enterprise_agent_platform\deploy\identity-vault\* ^
  VM_NAME:tch/
```

## 3. VM — Docker and tools

```
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
newgrp docker
sudo apt-get update
sudo apt-get install -y jq openssl
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

If `./run.sh` fails on `$'\r'`:

```
sudo apt-get install -y dos2unix
find ~/keycloak ~/openbao ~/tch -name '*.sh' -exec dos2unix {} \;
```

## 4. VM — Keycloak

```
cd ~/keycloak
cp .env.example .env
nano .env
```

Set hostnames and **two different** passwords (not `REPLACE_ME`). Then:

```
chmod +x run.sh
./run.sh
```

Console (master realm): `http://login.dev.xelerait.internal:8080/admin/`  
TCH users later: `http://login.dev.xelerait.internal:8080/realms/tch/account`

If DNS is not ready, put the VM IP in `/etc/hosts` for
`login.dev.xelerait.internal` and `openbao.dev.xelerait.internal`.

## 5. VM — OpenBao

```
cd ~/openbao
cp .env.example .env
nano .env
chmod +x run.sh generate-vm-certs.sh
./run.sh
```

If callers will use the VM IP instead of DNS, set `OPENBAO_EXTRA_SANS=IP:<INTERNAL_IP>`
**before** the first `./run.sh`.

## 6. VM — bootstrap

```
cd ~/keycloak
set -a; source .env; set +a

kcadm.sh() {
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}
export -f kcadm.sh

kcadm.sh config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USER" \
  --password "$KEYCLOAK_ADMIN_PASSWORD"

cd ~/tch
./scripts/bootstrap_keycloak.sh
```

Then OpenBao (same SSH session):

```
cd ~/openbao
export BAO_TOKEN
BAO_TOKEN="$(cat secrets/openbao-root-token.txt)"

bao() {
  docker compose exec -T \
    -e BAO_ADDR=https://127.0.0.1:8200 \
    -e BAO_CACERT=/openbao/certs/ca.crt \
    -e BAO_TOKEN \
    openbao bao "$@"
}
export -f bao

export KEYCLOAK_OIDC_SCHEME=http
export KEYCLOAK_OIDC_HOST=host.docker.internal:8080
export KEYCLOAK_ISSUER_HOST=login.dev.xelerait.internal:8080
export KEYCLOAK_REALM_NAME=tch

cd ~/tch
./scripts/bootstrap_openbao.sh
```

If humans open Keycloak by IP, set `KEYCLOAK_ISSUER_HOST=<INTERNAL_IP>:8080` instead.

## 7. Check

| What | Where |
|---|---|
| Keycloak admin (master) | `http://login.dev.xelerait.internal:8080/admin/` |
| TCH realm (app users) | `http://login.dev.xelerait.internal:8080/realms/tch/account` |
| OpenBao | `https://openbao.dev.xelerait.internal:8200/ui` (trust `~/openbao/certs/ca.crt`) |

OpenBao root token: `~/openbao/secrets/openbao-root-token.txt` — do not commit or paste it.

After a reboot: `~/keycloak/run.sh` then `~/openbao/run.sh`.

Firewall: TCP 22 from IAP `35.235.240.0/20`; TCP 8080 and 8200 to callers. Not 5432 or 8220.

## If SSH/SCP fails

| Error | Fix |
|---|---|
| `Reauthentication failed` | `gcloud auth login` |
| no IAP permission | **IAP-secured Tunnel User** on `xel-dev-platform` |
| timeout on port 22 | allow TCP 22 from `35.235.240.0/20` |
| `Permission denied (publickey)` | **Compute OS Login** (or a metadata SSH key) |
