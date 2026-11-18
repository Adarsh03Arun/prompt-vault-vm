from __future__ import annotations

import json
import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from audit_api.parser import parse_line
from audit_api.store import AuditStore, Query, cluster_publish_runs

FIXTURE = """\
{"time":"2026-11-16T08:00:00.000Z","type":"request","auth":{"display_name":"demo-reader.agents.internal"},"request":{"id":"r1","operation":"read","path":"secret/data/prompts/tch/demo/nursing_assistant_agent"}}
{"time":"2026-11-16T08:00:00.010Z","type":"response","auth":{"display_name":"demo-reader.agents.internal","entity_id":"e1"},"request":{"id":"r1","operation":"read","path":"secret/data/prompts/tch/demo/nursing_assistant_agent"}}
{"time":"2026-11-16T08:01:00.000Z","type":"response","auth":{"display_name":"demo-reader.agents.internal"},"request":{"id":"r2","operation":"read","path":"secret/data/prompts/tch/racc/x"},"error":"1 error occurred:\\n\\t* permission denied\\n\\n"}
{"time":"2026-11-16T08:02:00.000Z","type":"response","auth":{"display_name":"gitops-pipeline"},"request":{"id":"r3","operation":"update","path":"secret/data/prompts/tch/demo/safeguard_agent"}}
{"time":"2026-11-16T08:02:05.000Z","type":"response","auth":{"display_name":"gitops-pipeline"},"request":{"id":"r4","operation":"update","path":"secret/data/agent-certs/tch/demo"}}
{"time":"2026-11-16T08:03:00.000Z","type":"response","auth":{"display_name":"vault-admin@realm"},"request":{"id":"r5","operation":"update","path":"secret/metadata/prompts/tch/demo/output_judge_agent"}}
{"time":"2026-11-16T08:04:00.000Z","type":"response","auth":{"display_name":"agent-cert-auth"},"request":{"id":"r6","operation":"update","path":"auth/cert/login"}}
"""


@pytest.fixture()
def audit_file(tmp_path: Path) -> Path:
    p = tmp_path / "audit.log"
    p.write_text(FIXTURE, encoding="utf-8")
    return p


def test_parse_skips_request_only():
    line = FIXTURE.splitlines()[0]
    assert parse_line(line) is None


def test_parse_allowed_and_denied(audit_file: Path):
    store = AuditStore(str(audit_file))
    events = store.all_events()
    assert events[0].result == "allowed" or events[-1].result in ("allowed", "denied")
    denied = [e for e in events if e.result == "denied"]
    assert len(denied) == 1
    assert denied[0].space == "racc"


def test_filter_space(audit_file: Path):
    store = AuditStore(str(audit_file))
    page = store.filter(Query(space="demo", limit=100))
    assert all(e.space == "demo" for e in page)
    assert len(page) >= 2


def test_summary(audit_file: Path):
    store = AuditStore(str(audit_file))
    s = store.summary(Query(limit=10**6))
    assert s["totals"]["events"] >= 4
    assert "read" in s["by_action"] or "update" in s["by_action"]


def test_cluster_publish(audit_file: Path):
    store = AuditStore(str(audit_file))
    runs = cluster_publish_runs(store.all_events(), cluster_seconds=120)
    assert runs
    assert any(runs[0]["published"] or runs[0]["cert_writes"])


@pytest.fixture()
def client(audit_file: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("OPENBAO_AUDIT_LOG_PATH", str(audit_file))
    monkeypatch.setenv("AUDIT_API_TOKEN", "test-token")
    # Reset cached settings
    from audit_api import app as app_mod

    app_mod.get_settings.cache_clear()
    return TestClient(app_mod.app)


def test_unauthorized(client: TestClient):
    res = client.get("/api/audit")
    assert res.status_code == 401


def test_l1_and_l7(client: TestClient):
    headers = {"Authorization": "Bearer test-token"}
    r1 = client.get("/api/audit", headers=headers)
    assert r1.status_code == 200
    assert "entries" in r1.json()
    r7 = client.get("/api/audit/events", headers=headers, params={"space": "demo"})
    assert r7.status_code == 200
    body = r7.json()
    assert "items" in body
    assert all(i["space"] == "demo" for i in body["items"])


def test_l10_l14_l16(client: TestClient):
    headers = {"Authorization": "Bearer test-token"}
    assert client.get("/api/audit/summary", headers=headers).status_code == 200
    assert client.get("/api/logs/agent-reads", headers=headers).status_code == 200
    fails = client.get("/api/logs/auth-failures", headers=headers)
    assert fails.status_code == 200
    assert all(i["result"] == "denied" for i in fails.json()["items"])


def test_l11_publish_runs(client: TestClient):
    headers = {"Authorization": "Bearer test-token"}
    res = client.get("/api/logs/publish-runs", headers=headers)
    assert res.status_code == 200
    assert "items" in res.json()
