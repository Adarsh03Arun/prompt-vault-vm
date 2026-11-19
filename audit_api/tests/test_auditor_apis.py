"""Auditor review APIs — demo catalogue (read-only)."""

from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("OPENBAO_AUDIT_LOG_PATH", "audit_api/tests/fixtures/audit.sample.log")
os.environ.setdefault("AUDIT_API_TOKEN", "test-token")

from audit_api.app import app  # noqa: E402


@pytest.fixture()
def client():
    from audit_api import app as app_mod

    app_mod.get_settings.cache_clear()
    return TestClient(app)


def _auth():
    return {"Authorization": "Bearer test-token"}


def test_list_agents(client: TestClient):
    res = client.get("/api/auditor/agents", headers=_auth())
    assert res.status_code == 200
    items = res.json()["items"]
    assert items
    assert "display_name" in items[0]
    assert "system_prompt" not in items[0]


def test_versions_and_prompt(client: TestClient):
    res = client.get(
        "/api/auditor/agents/care-floor/bedside_triage_assistant/versions",
        headers=_auth(),
    )
    assert res.status_code == 200
    versions = res.json()["items"]
    assert any(v["status"] == "live" for v in versions)
    assert any(v["status"] == "deprecated" for v in versions)

    live = next(v for v in versions if v["status"] == "live")
    prompt = client.get(
        "/api/auditor/agents/care-floor/bedside_triage_assistant/prompt",
        params={"version": live["version"]},
        headers=_auth(),
    )
    assert prompt.status_code == 200
    body = prompt.json()
    assert body["system_prompt"]["text"]
    assert "triage" in body["system_prompt"]["text"].lower()


def test_changes_include_deprecation(client: TestClient):
    res = client.get(
        "/api/auditor/agents/care-floor/bedside_triage_assistant/changes",
        headers=_auth(),
    )
    assert res.status_code == 200
    actions = {c["action"] for c in res.json()["items"]}
    assert "deprecated" in actions
    assert "published" in actions


def test_unauthorized(client: TestClient):
    assert client.get("/api/auditor/agents").status_code == 401
