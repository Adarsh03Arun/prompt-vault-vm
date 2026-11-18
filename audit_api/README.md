# Prompt Vault Audit API (Python)

Small **FastAPI** service meant to run **on the OpenBao / Prompt Vault VM**.  
It reads OpenBao’s audit file from disk and exposes the internal-dashboard log APIs (L1, L7–L16) from [`docs/apis/logs-apis.md`](../docs/apis/logs-apis.md).

Not included (stay on OpenBao / Admin UI): L2 health via Admin, L3–L6 `sys/audit*` device management, Publish Gate.

## Why on the vault VM

`GET /api/audit` in the Admin UI only works when the backend can read the audit file. Putting this service on the OpenBao host is the straightforward deploy: no log shipping required for v1.

## Endpoints

| API | Catalogue |
|---|---|
| `GET /healthz` | liveness (no auth) |
| `GET /readyz` | audit file readable |
| `GET /api/audit` | L1 |
| `GET /api/audit/events` | L7 |
| `GET /api/audit/events/{id}` | L8 |
| `GET /api/audit/export?format=jsonl\|csv` | L9 |
| `GET /api/audit/summary` | L10 |
| `GET /api/logs/publish-runs` | L11 (synthetic clusters from audit) |
| `GET /api/logs/publish-runs/{run_id}` | L12 |
| `GET /api/logs/cert-renewals` | L13 |
| `GET /api/logs/agent-reads` | L14 |
| `GET /api/logs/human-admin` | L15 |
| `GET /api/logs/auth-failures` | L16 |

All routes except `/healthz` require:

```http
Authorization: Bearer <AUDIT_API_TOKEN>
```

## Environment

| Variable | Required | Meaning |
|---|---|---|
| `OPENBAO_AUDIT_LOG_PATH` | yes | e.g. `/var/log/openbao/audit.log` |
| `AUDIT_API_TOKEN` | yes | Shared secret for the internal dashboard |
| `AUDIT_API_HOST` | no | default `0.0.0.0` |
| `AUDIT_API_PORT` | no | default `8088` |
| `AUDIT_API_MAX_SCAN_LINES` | no | default `500000` |
| `AUDIT_API_DEFAULT_LIMIT` | no | default `200` |
| `AUDIT_API_MAX_LIMIT` | no | default `2000` |

## Run on the VM

```bash
cd prompt-vault-tch
python -m venv .venv-audit
source .venv-audit/bin/activate
pip install -r audit_api/requirements.txt

export OPENBAO_AUDIT_LOG_PATH=/path/to/openbao/audit.log
export AUDIT_API_TOKEN='(long random secret)'
python -m audit_api
```

Or:

```bash
uvicorn audit_api.app:app --host 0.0.0.0 --port 8088
```

Bind firewall to private network / VPN only. Do not expose this port publicly.

### systemd sketch

```ini
[Unit]
Description=Prompt Vault Audit API
After=network.target

[Service]
WorkingDirectory=/opt/prompt-vault-tch
Environment=OPENBAO_AUDIT_LOG_PATH=/var/log/openbao/audit.log
EnvironmentFile=-/etc/prompt-vault/audit-api.env
ExecStart=/opt/prompt-vault-tch/.venv-audit/bin/python -m audit_api
Restart=on-failure
User=openbao
Group=openbao

[Install]
WantedBy=multi-user.target
```

Put `AUDIT_API_TOKEN=...` in `/etc/prompt-vault/audit-api.env` (mode 600).

## Smoke

Full VM deploy + curl checklist: [`VM_DEPLOY_AND_TEST.md`](./VM_DEPLOY_AND_TEST.md).

```bash
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" \
  "http://127.0.0.1:8088/api/audit?limit=5" | jq .

curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" \
  "http://127.0.0.1:8088/api/audit/summary" | jq .
```

## Tests

```bash
cd prompt-vault-tch
pip install -r audit_api/requirements.txt
pytest audit_api/tests -q
```

## Notes for seniors

- **v1** tails/parses the audit file in-process (with mtime cache). Fine for a single VM and moderate volume; for multi-node or huge files, ship JSONL to ClickHouse/Loki and keep the same HTTP shapes.
- **L11/L12** do not call GitHub. They cluster `gitops-pipeline` writes by time. Optional later: enrich with Actions run ids.
- Responses never include prompt bodies or tokens — only paths, identities, and outcomes.
