"""FastAPI audit / logs service for the Prompt Vault (OpenBao) VM.

Deploy on the same host as OpenBao so it can read the audit file.
Implements catalogue endpoints L1 and L7–L16 (see docs/apis/logs-apis.md).
L2–L6 stay on OpenBao / Admin UI.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse, PlainTextResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from .auth import build_auth_dependency
from .config import Settings
from .store import AuditStore, Query as StoreQuery, cluster_publish_runs

app = FastAPI(
    title="Prompt Vault Audit API",
    version="0.1.0",
    description="Server-side audit/log query APIs for the internal dashboard (Python).",
)

_UI_DIR = Path(__file__).resolve().parent / "ui"
if _UI_DIR.is_dir():
    app.mount("/ui", StaticFiles(directory=str(_UI_DIR), html=True), name="ui")


@app.get("/", include_in_schema=False)
def root_to_ui() -> RedirectResponse:
    return RedirectResponse(url="/ui/")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings.from_env()


def get_store() -> AuditStore:
    s = get_settings()
    return AuditStore(s.audit_log_path, max_scan_lines=s.max_scan_lines)


Auth = build_auth_dependency(get_settings)


def _clamp_limit(raw: int | None) -> int:
    s = get_settings()
    if raw is None:
        return s.default_limit
    return max(1, min(raw, s.max_limit))


def _store_query(
    *,
    from_: str | None,
    to: str | None,
    environment: str | None,
    space: str | None,
    agent: str | None,
    who: str | None,
    action: str | None,
    result: str | None,
    path_prefix: str | None,
    mount: str | None,
    category: str | None,
    q: str | None,
    limit: int | None,
    cursor: int | None,
) -> StoreQuery:
    return StoreQuery(
        from_time=from_,
        to_time=to,
        environment=environment,
        space=space,
        agent=agent,
        who=who,
        action=action,
        result=result,
        path_prefix=path_prefix,
        mount=mount,
        category=category,
        q=q,
        limit=_clamp_limit(limit),
        cursor=cursor or 0,
    )


def _load_page(store_q: StoreQuery):
    try:
        return get_store().page(store_q)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


def _load_filter(store_q: StoreQuery):
    try:
        return get_store().filter(store_q)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.get("/readyz")
def readyz(_auth: None = Auth) -> dict:
    try:
        get_store().all_events()
    except FileNotFoundError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"ok": True, "audit_log_path": get_settings().audit_log_path}


@app.get("/api/audit")
def list_audit(_auth: None = Auth, limit: int | None = Query(None)) -> dict:
    """L1 — recent vault activity."""
    q = _store_query(
        from_=None,
        to=None,
        environment=None,
        space=None,
        agent=None,
        who=None,
        action=None,
        result=None,
        path_prefix=None,
        mount=None,
        category=None,
        q=None,
        limit=limit,
        cursor=0,
    )
    page, _ = _load_page(q)
    return {"entries": [e.to_l1() for e in page]}


@app.get("/api/audit/events")
def search_events(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    environment: str | None = None,
    space: str | None = None,
    agent: str | None = None,
    who: str | None = None,
    action: str | None = None,
    result: Literal["allowed", "denied"] | None = None,
    path_prefix: str | None = None,
    mount: str | None = None,
    category: str | None = None,
    q: str | None = None,
    limit: int | None = None,
    cursor: int | None = None,
) -> dict:
    """L7 — filtered, paginated search."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=environment,
        space=space,
        agent=agent,
        who=who,
        action=action,
        result=result,
        path_prefix=path_prefix,
        mount=mount,
        category=category,
        q=q,
        limit=limit,
        cursor=cursor,
    )
    page, next_cursor = _load_page(store_q)
    return {"items": [e.to_dict() for e in page], "next_cursor": next_cursor, "limit": store_q.limit}


@app.get("/api/audit/events/{event_id}")
def get_event(event_id: str, _auth: None = Auth) -> dict:
    """L8 — single event."""
    try:
        events = get_store().all_events()
    except FileNotFoundError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    for ev in events:
        if ev.id == event_id:
            return {"event": ev.to_dict()}
    raise HTTPException(status_code=404, detail="Event not found")


@app.get("/api/audit/export")
def export_events(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    environment: str | None = None,
    space: str | None = None,
    agent: str | None = None,
    who: str | None = None,
    action: str | None = None,
    result: Literal["allowed", "denied"] | None = None,
    path_prefix: str | None = None,
    mount: str | None = None,
    category: str | None = None,
    q: str | None = None,
    format: Literal["jsonl", "csv"] = "jsonl",
):
    """L9 — export matching events."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=environment,
        space=space,
        agent=agent,
        who=who,
        action=action,
        result=result,
        path_prefix=path_prefix,
        mount=mount,
        category=category,
        q=q,
        limit=get_settings().max_limit,
        cursor=0,
    )
    store_q.limit = 10**9
    try:
        store = get_store()
        if format == "csv":
            return PlainTextResponse(store.export_csv(store_q), media_type="text/csv")
        return PlainTextResponse(store.export_jsonl(store_q), media_type="application/x-ndjson")
    except FileNotFoundError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.get("/api/audit/summary")
def summary(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    environment: str | None = None,
    space: str | None = None,
) -> dict:
    """L10 — server-side aggregates for charts."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=environment,
        space=space,
        agent=None,
        who=None,
        action=None,
        result=None,
        path_prefix=None,
        mount=None,
        category=None,
        q=None,
        limit=get_settings().max_limit,
        cursor=0,
    )
    store_q.limit = 10**9
    try:
        return get_store().summary(store_q)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.get("/api/logs/publish-runs")
def publish_runs(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    limit: int | None = None,
) -> dict:
    """L11 — synthetic publish clusters from OpenBao audit (no GitHub API required)."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=None,
        space=None,
        agent=None,
        who=None,
        action=None,
        result=None,
        path_prefix=None,
        mount=None,
        category=None,
        q=None,
        limit=limit,
        cursor=0,
    )
    matched = _load_filter(store_q)
    runs = cluster_publish_runs(
        matched, cluster_seconds=get_settings().publish_cluster_seconds
    )
    return {"items": runs[: _clamp_limit(limit)]}


@app.get("/api/logs/publish-runs/{run_id}")
def publish_run_detail(run_id: str, _auth: None = Auth) -> dict:
    """L12 — one publish cluster + its vault events."""
    try:
        events = get_store().all_events()
    except FileNotFoundError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    runs = cluster_publish_runs(
        events, cluster_seconds=get_settings().publish_cluster_seconds
    )
    for run in runs:
        if run["run_id"] == run_id:
            ids = set(run["event_ids"])
            return {
                "run": run,
                "events": [e.to_dict() for e in events if e.id in ids],
            }
    raise HTTPException(status_code=404, detail="Publish run not found")


@app.get("/api/logs/cert-renewals")
def cert_renewals(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    space: str | None = None,
    limit: int | None = None,
) -> dict:
    """L13 — agent-certs KV activity."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=None,
        space=space,
        agent=None,
        who=None,
        action=None,
        result=None,
        path_prefix="secret/data/agent-certs/",
        mount=None,
        category=None,
        q=None,
        limit=limit,
        cursor=0,
    )
    page, next_cursor = _load_page(store_q)
    items = [
        e.to_dict()
        for e in page
        if e.category.startswith("cert.") or e.target.startswith("secret/data/agent-certs/")
    ]
    return {"items": items, "next_cursor": next_cursor}


@app.get("/api/logs/agent-reads")
def agent_reads(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    space: str | None = None,
    agent: str | None = None,
    limit: int | None = None,
    cursor: int | None = None,
) -> dict:
    """L14 — mTLS login + prompt reads."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=None,
        space=space,
        agent=agent,
        who=None,
        action=None,
        result=None,
        path_prefix=None,
        mount=None,
        category=None,
        q=None,
        limit=limit,
        cursor=cursor,
    )
    matched = _load_filter(store_q)
    filtered = [
        e
        for e in matched
        if e.category in ("auth.cert.login", "prompt.read", "prompt.list", "prompt.metadata")
        or e.mount == "auth/cert"
    ]
    start = store_q.cursor
    end = start + store_q.limit
    page = filtered[start:end]
    next_cursor = end if end < len(filtered) else None
    return {"items": [e.to_dict() for e in page], "next_cursor": next_cursor}


@app.get("/api/logs/human-admin")
def human_admin(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    limit: int | None = None,
    cursor: int | None = None,
) -> dict:
    """L15 — human / admin UI shaped activity."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=None,
        space=None,
        agent=None,
        who=None,
        action=None,
        result=None,
        path_prefix=None,
        mount=None,
        category=None,
        q=None,
        limit=limit,
        cursor=cursor,
    )
    matched = _load_filter(store_q)

    def is_human(e) -> bool:
        if e.category in (
            "auth.jwt.login",
            "auth.github.login",
            "prompt.metadata",
            "prompt.delete",
            "prompt.undelete",
        ):
            return True
        if "@" in e.who and "gitops" not in e.who and "reader.agents.internal" not in e.who:
            return True
        if e.who.startswith("vault-"):
            return True
        return False

    filtered = [e for e in matched if is_human(e)]
    start = store_q.cursor
    end = start + store_q.limit
    page = filtered[start:end]
    next_cursor = end if end < len(filtered) else None
    return {"items": [e.to_dict() for e in page], "next_cursor": next_cursor}


@app.get("/api/logs/auth-failures")
def auth_failures(
    _auth: None = Auth,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    mount: str | None = None,
    limit: int | None = None,
    cursor: int | None = None,
) -> dict:
    """L16 — denied auth / ACL only."""
    store_q = _store_query(
        from_=from_,
        to=to,
        environment=None,
        space=None,
        agent=None,
        who=None,
        action=None,
        result="denied",
        path_prefix=None,
        mount=mount,
        category=None,
        q=None,
        limit=limit,
        cursor=cursor,
    )
    page, next_cursor = _load_page(store_q)
    return {"items": [e.to_dict() for e in page], "next_cursor": next_cursor}


@app.exception_handler(HTTPException)
async def http_exc_handler(_request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})
