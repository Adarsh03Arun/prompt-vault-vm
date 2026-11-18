"""Playwright API tests against a live uvicorn audit_api process."""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest
from playwright.sync_api import APIRequestContext, Playwright

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_LOG = ROOT / "audit_api" / "tests" / "fixtures" / "audit.sample.log"

SAMPLE = """\
{"time":"2026-11-16T08:00:00.010Z","type":"response","auth":{"display_name":"demo-reader.agents.internal","entity_id":"e1"},"request":{"id":"r1","operation":"read","path":"secret/data/prompts/tch/demo/nursing_assistant_agent"}}
{"time":"2026-11-16T08:01:00.000Z","type":"response","auth":{"display_name":"demo-reader.agents.internal"},"request":{"id":"r2","operation":"read","path":"secret/data/prompts/tch/racc/x"},"error":"permission denied"}
{"time":"2026-11-16T08:02:00.000Z","type":"response","auth":{"display_name":"gitops-pipeline"},"request":{"id":"r3","operation":"update","path":"secret/data/prompts/tch/demo/safeguard_agent"}}
{"time":"2026-11-16T08:02:05.000Z","type":"response","auth":{"display_name":"gitops-pipeline"},"request":{"id":"r4","operation":"update","path":"secret/data/agent-certs/tch/demo"}}
{"time":"2026-11-16T08:03:00.000Z","type":"response","auth":{"display_name":"vault-admin@realm"},"request":{"id":"r5","operation":"update","path":"secret/metadata/prompts/tch/demo/output_judge_agent"}}
{"time":"2026-11-16T08:04:00.000Z","type":"response","auth":{"display_name":"demo-reader.agents.internal"},"request":{"id":"r6","operation":"update","path":"auth/cert/login"}}
"""

TOKEN = "playwright-audit-token"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def audit_server():
    FIXTURE_LOG.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_LOG.write_text(SAMPLE, encoding="utf-8")
    port = _free_port()
    env = os.environ.copy()
    env["OPENBAO_AUDIT_LOG_PATH"] = str(FIXTURE_LOG)
    env["AUDIT_API_TOKEN"] = TOKEN
    env["AUDIT_API_HOST"] = "127.0.0.1"
    env["AUDIT_API_PORT"] = str(port)
    env["PYTHONPATH"] = str(ROOT) + os.pathsep + env.get("PYTHONPATH", "")

    proc = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "audit_api.app:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
        ],
        cwd=str(ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + 20
    last_err = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read() if proc.stdout else ""
            raise RuntimeError(f"uvicorn exited early: {out}")
        try:
            import urllib.request

            urllib.request.urlopen(base + "/healthz", timeout=0.5)
            break
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(0.2)
    else:
        proc.kill()
        raise RuntimeError(f"server did not start: {last_err}")

    yield base
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


@pytest.fixture(scope="module")
def api(playwright: Playwright, audit_server: str) -> APIRequestContext:
    ctx = playwright.request.new_context(
        base_url=audit_server,
        extra_http_headers={"Authorization": f"Bearer {TOKEN}"},
    )
    yield ctx
    ctx.dispose()


def test_healthz(playwright: Playwright, audit_server: str):
    ctx = playwright.request.new_context(base_url=audit_server)
    res = ctx.get("/healthz")
    assert res.ok
    assert res.json()["ok"] is True
    ctx.dispose()


def test_readyz(api: APIRequestContext):
    res = api.get("/readyz")
    assert res.ok
    body = res.json()
    assert body["ok"] is True
    assert "audit_log_path" in body


def test_unauthorized(playwright: Playwright, audit_server: str):
    ctx = playwright.request.new_context(base_url=audit_server)
    res = ctx.get("/api/audit")
    assert res.status == 401
    ctx.dispose()


def test_l1_audit(api: APIRequestContext):
    res = api.get("/api/audit", params={"limit": 10})
    assert res.ok, res.text()
    entries = res.json()["entries"]
    assert isinstance(entries, list)
    assert entries
    assert {"time", "who", "action", "target", "environment", "result"} <= set(entries[0])


def test_l7_events(api: APIRequestContext):
    res = api.get("/api/audit/events", params={"space": "demo", "limit": 50})
    assert res.ok, res.text()
    body = res.json()
    assert "items" in body
    assert all(i["space"] == "demo" for i in body["items"])


def test_l8_event_detail(api: APIRequestContext):
    listing = api.get("/api/audit/events", params={"limit": 5})
    assert listing.ok
    items = listing.json()["items"]
    assert items
    event_id = items[0]["id"]
    res = api.get(f"/api/audit/events/{event_id}")
    assert res.ok, res.text()
    assert res.json()["event"]["id"] == event_id


def test_l9_export_jsonl_and_csv(api: APIRequestContext):
    j = api.get("/api/audit/export", params={"format": "jsonl"})
    assert j.ok, j.text()
    assert "application/x-ndjson" in (j.headers.get("content-type") or "")
    assert j.text().strip()

    c = api.get("/api/audit/export", params={"format": "csv"})
    assert c.ok, c.text()
    assert "text/csv" in (c.headers.get("content-type") or "")
    assert "id,time,who" in c.text().splitlines()[0]


def test_l10_summary(api: APIRequestContext):
    res = api.get("/api/audit/summary")
    assert res.ok, res.text()
    body = res.json()
    assert "totals" in body
    assert body["totals"]["events"] >= 1
    assert "by_action" in body


def test_l11_l12_publish_runs(api: APIRequestContext):
    res = api.get("/api/logs/publish-runs")
    assert res.ok, res.text()
    items = res.json()["items"]
    assert isinstance(items, list)
    if items:
        run_id = items[0]["run_id"]
        detail = api.get(f"/api/logs/publish-runs/{run_id}")
        assert detail.ok, detail.text()
        assert detail.json()["run"]["run_id"] == run_id
        assert "events" in detail.json()


def test_l13_cert_renewals(api: APIRequestContext):
    res = api.get("/api/logs/cert-renewals")
    assert res.ok, res.text()
    items = res.json()["items"]
    assert any("agent-certs" in i["target"] for i in items)


def test_l14_agent_reads(api: APIRequestContext):
    res = api.get("/api/logs/agent-reads")
    assert res.ok, res.text()
    items = res.json()["items"]
    assert items
    assert any(i["category"] in ("prompt.read", "auth.cert.login") for i in items)


def test_l15_human_admin(api: APIRequestContext):
    res = api.get("/api/logs/human-admin")
    assert res.ok, res.text()
    items = res.json()["items"]
    assert any("vault-admin" in i["who"] or i["category"] == "prompt.metadata" for i in items)


def test_l16_auth_failures(api: APIRequestContext):
    res = api.get("/api/logs/auth-failures")
    assert res.ok, res.text()
    items = res.json()["items"]
    assert items
    assert all(i["result"] == "denied" for i in items)
