# Audit API — VM deploy and curl test commands

Commands used to deploy `audit_api` on `xel-openbao-keycloak-dev` and verify L1 / L7–L16 against the live OpenBao audit file. No separate audit DB required.

## Prerequisites on the VM

```bash
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip jq
```

Audit log (OpenBao docker mount):

```bash
ls -la ~/openbao/logs/audit.log
```

## Get the code

### Preferred if you use `prompt-vault-vm` on the VM

```bash
cd ~/tch
git remote set-url origin https://github.com/Adarsh03Arun/prompt-vault-vm.git
git fetch origin
git checkout main
git pull origin main
ls audit_api
```

### Or from `XelerAIT-Solutions/tch` (`prompt-vault` branch)

Requires a PAT/SSH with **read** access to the org repo (authorize SSO for `XelerAIT-Solutions` if using a fine-grained token).

```bash
cd ~
git clone -b prompt-vault https://github.com/XelerAIT-Solutions/tch.git tch-prompt-vault
cd ~/tch-prompt-vault/prompt-vault-tch
ls audit_api
```

## Fix audit.log permissions (common Errno 13)

If `/readyz` or audit routes return permission denied:

```bash
ls -la ~/openbao/logs/
sudo chmod 755 ~/openbao/logs
sudo chmod 644 ~/openbao/logs/audit.log
# or:
sudo chown -R "$USER:$USER" ~/openbao/logs

# confirm your user can read
head -1 ~/openbao/logs/audit.log
```

## Create venv and install

From the directory that **contains** the `audit_api/` package (`~/tch` for prompt-vault-vm, or `…/prompt-vault-tch` for the tch clone):

```bash
cd ~/tch   # or: cd ~/tch-prompt-vault/prompt-vault-tch

rm -rf .venv-audit
python3 -m venv .venv-audit
source .venv-audit/bin/activate
pip install -r audit_api/requirements.txt
```

## Token and env

```bash
TOKEN=$(openssl rand -hex 32)
echo "$TOKEN" | tee ~/audit_api.token
chmod 600 ~/audit_api.token

export OPENBAO_AUDIT_LOG_PATH=$HOME/openbao/logs/audit.log
export AUDIT_API_TOKEN=$(cat ~/audit_api.token)
export PYTHONPATH=$PWD
```

Optional persistent env file:

```bash
sudo mkdir -p /etc/prompt-vault
echo "AUDIT_API_TOKEN=$(cat ~/audit_api.token)" | sudo tee /etc/prompt-vault/audit-api.env
sudo chmod 600 /etc/prompt-vault/audit-api.env
```

## Start the service (foreground)

```bash
cd ~/tch   # or prompt-vault-tch path
source .venv-audit/bin/activate
export OPENBAO_AUDIT_LOG_PATH=$HOME/openbao/logs/audit.log
export AUDIT_API_TOKEN=$(cat ~/audit_api.token)
export PYTHONPATH=$PWD

python -m uvicorn audit_api.app:app --host 127.0.0.1 --port 8088
```

Leave this session open. Expect:

```text
Uvicorn running on http://127.0.0.1:8088
```

## Curl tests (second SSH session)

```bash
export BASE=http://127.0.0.1:8088
export AUDIT_API_TOKEN=$(cat ~/audit_api.token)

# listening?
ss -lntp | grep 8088

# health (no auth)
curl -sS "$BASE/healthz" | jq .

# ready (needs readable audit file + bearer)
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/readyz" | jq .

# L1
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/audit?limit=5" | jq .

# L7
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/audit/events?limit=20" | jq .

# L8 — use an id from L7 items[].id
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/audit/events/<EVENT_ID>" | jq .

# L9
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/audit/export?format=jsonl" | head
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/audit/export?format=csv" | head

# L10
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/audit/summary" | jq .

# L11–L16
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/logs/publish-runs" | jq .
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/logs/publish-runs/<RUN_ID>" | jq .
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/logs/cert-renewals" | jq .
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/logs/agent-reads" | jq .
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/logs/human-admin" | jq .
curl -sS -H "Authorization: Bearer $AUDIT_API_TOKEN" "$BASE/api/logs/auth-failures" | jq .

# expect 401
curl -sS -o /dev/null -w "%{http_code}\n" "$BASE/api/audit"
```

### One-shot smoke (copy/paste)

```bash
export BASE=http://127.0.0.1:8088
export AUDIT_API_TOKEN=$(cat ~/audit_api.token)
H=(-H "Authorization: Bearer $AUDIT_API_TOKEN")

curl -sS "$BASE/healthz" | jq .
curl -sS "${H[@]}" "$BASE/readyz" | jq .
curl -sS "${H[@]}" "$BASE/api/audit?limit=5" | jq .
curl -sS "${H[@]}" "$BASE/api/audit/events?limit=10" | jq '{count:(.items|length), next_cursor}'
curl -sS "${H[@]}" "$BASE/api/audit/summary" | jq .totals
curl -sS "${H[@]}" "$BASE/api/logs/publish-runs" | jq '{count:(.items|length)}'
curl -sS "${H[@]}" "$BASE/api/logs/cert-renewals" | jq '{count:(.items|length)}'
curl -sS "${H[@]}" "$BASE/api/logs/agent-reads" | jq '{count:(.items|length)}'
curl -sS "${H[@]}" "$BASE/api/logs/human-admin" | jq '{count:(.items|length)}'
curl -sS "${H[@]}" "$BASE/api/logs/auth-failures" | jq '{count:(.items|length)}'
curl -sS -o /dev/null -w "unauth=%{http_code}\n" "$BASE/api/audit"
```

## Local Playwright tests (laptop / CI — not the VM)

Does **not** hit the VM; starts local uvicorn + sample log:

```bash
cd prompt-vault-tch   # or repo path that contains audit_api/
python -m pip install -r audit_api/requirements.txt
python -m playwright install chromium
python -m pytest audit_api/tests/test_playwright_apis.py -v
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not connect to … :8088` | Service not running — start uvicorn |
| `ensurepip is not available` / `python: command not found` | `sudo apt-get install -y python3-venv python3-pip`; use `python3` |
| `readyz` / APIs → permission denied on `audit.log` | `chmod`/`chown` on `~/openbao/logs` (see above) |
| `401` on authenticated routes | Wrong/missing `AUDIT_API_TOKEN` |
| `401` **without** header on `/api/audit` | Expected |
| Git `403 Write access…` to `XelerAIT-Solutions/tch` | PAT lacks org repo access / SSO not authorized — use `prompt-vault-vm` remote or fix PAT |
| L11 `publish-runs` empty | No clustered gitops publish activity in the audit window — OK |

## Expected healthy smoke (live VM)

- `healthz` / `readyz` → `"ok": true`
- L1/L7/L10 and L13–L16 → HTTP 200 with data from OpenBao audit
- Unauthenticated `/api/audit` → `401`
