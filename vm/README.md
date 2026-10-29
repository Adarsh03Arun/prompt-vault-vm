# One VM, two folders

Laptop Compose stays in `../docker/`. Terraform stays on hold.

| On the VM | What | Ports |
|---|---|---|
| `~/keycloak` | Shared IAM: Keycloak + Postgres | `:8080` (humans), `127.0.0.1:5432` |
| `~/openbao` | Prompt vault: OpenBao + unsealer | `:8200` (agents/GitOps), `127.0.0.1:8220` |

Keycloak is **not** under a vault path — other services will use it too.
OpenBao and the unsealer share one folder.

Copy commands are in `gcloud.md`. Bring-up: Keycloak first, then OpenBao.

```
cd ~/keycloak && cp .env.example .env && ./run.sh
cd ~/openbao  && cp .env.example .env && ./run.sh
```

Then bootstrap scripts from the identity-vault tree (realm, policies,
`spaces.yaml`). OpenBao reaches Keycloak at
`host.docker.internal:8080` (`KEYCLOAK_OIDC_SCHEME=http`).
