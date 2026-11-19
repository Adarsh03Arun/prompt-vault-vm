# Auditor review APIs (read-only)

Product-agnostic APIs for humans who need to **review agent system prompts**, **versions**, and **deprecations**.  
They do **not** write to OpenBao or GitHub.

Auth (same as other audit routes):

```http
Authorization: Bearer <AUDIT_API_TOKEN>
```

UI: `GET /ui/` (Prompt review screen).

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/auditor/spaces` | List spaces |
| GET | `/api/auditor/agents?space=&q=` | List agents (search / filter) |
| GET | `/api/auditor/agents/{space}/{agent}` | Agent summary |
| GET | `/api/auditor/agents/{space}/{agent}/versions` | Versions + status (`live`, `deprecated`, `destroyed`, `soft_deleted`) |
| GET | `/api/auditor/agents/{space}/{agent}/prompt?version=` | **`system_prompt.text`** for a version (omit `version` → current live) |
| GET | `/api/auditor/agents/{space}/{agent}/changes` | Publish / deprecate / destroy / soft-delete history |

## Notes

- v1 responses come from an in-memory **demo catalogue** so auditors can review the flow without vault credentials.
- Live OpenBao-backed reads can be wired later behind the same paths (still GET-only).
- Destroyed versions return no prompt text + `unavailable_reason`.

## Curl examples

```bash
export BASE=http://127.0.0.1:8088
export AUDIT_API_TOKEN=local-demo-token
H=(-H "Authorization: Bearer $AUDIT_API_TOKEN")

curl -sS "${H[@]}" "$BASE/api/auditor/agents" | jq .
curl -sS "${H[@]}" "$BASE/api/auditor/agents/care-floor/bedside_triage_assistant/versions" | jq .
curl -sS "${H[@]}" "$BASE/api/auditor/agents/care-floor/bedside_triage_assistant/prompt?version=12" | jq -r .system_prompt.text
curl -sS "${H[@]}" "$BASE/api/auditor/agents/care-floor/bedside_triage_assistant/changes" | jq .
```
