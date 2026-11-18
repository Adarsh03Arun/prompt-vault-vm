"""Read and query the OpenBao audit file on local disk."""

from __future__ import annotations

import csv
import io
import json
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from .parser import AuditEvent, parse_line


def _parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


@dataclass
class Query:
    from_time: str | None = None
    to_time: str | None = None
    environment: str | None = None
    space: str | None = None
    agent: str | None = None
    who: str | None = None
    action: str | None = None
    result: str | None = None
    path_prefix: str | None = None
    mount: str | None = None
    category: str | None = None
    q: str | None = None
    limit: int = 200
    cursor: int = 0  # offset into newest-first list


class AuditStore:
    def __init__(self, path: str, *, max_scan_lines: int = 500_000) -> None:
        self.path = Path(path)
        self.max_scan_lines = max_scan_lines
        self._mtime: float | None = None
        self._events: list[AuditEvent] = []

    def _reload_if_needed(self) -> None:
        if not self.path.is_file():
            raise FileNotFoundError(f"Audit log not found: {self.path}")
        mtime = self.path.stat().st_mtime
        if self._mtime == mtime and self._events:
            return
        events: list[AuditEvent] = []
        # Read from the end for large files without loading everything twice.
        with self.path.open("r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
        if len(lines) > self.max_scan_lines:
            lines = lines[-self.max_scan_lines :]
        for line in lines:
            ev = parse_line(line)
            if ev:
                events.append(ev)
        # Newest first
        events.reverse()
        self._events = events
        self._mtime = mtime

    def all_events(self) -> list[AuditEvent]:
        self._reload_if_needed()
        return list(self._events)

    def filter(self, query: Query) -> list[AuditEvent]:
        self._reload_if_needed()
        from_dt = _parse_time(query.from_time)
        to_dt = _parse_time(query.to_time)
        q = (query.q or "").strip().lower()

        out: list[AuditEvent] = []
        for ev in self._events:
            if from_dt or to_dt:
                ts = _parse_time(ev.time)
                if ts is None:
                    continue
                if from_dt and ts < from_dt:
                    continue
                if to_dt and ts > to_dt:
                    continue
            if query.environment and ev.environment != query.environment:
                continue
            if query.space and ev.space != query.space:
                continue
            if query.agent and ev.agent != query.agent:
                continue
            if query.who and query.who.lower() not in ev.who.lower():
                continue
            if query.action and ev.action != query.action:
                continue
            if query.result and ev.result != query.result:
                continue
            if query.path_prefix and not ev.target.startswith(query.path_prefix):
                continue
            if query.mount and ev.mount != query.mount:
                continue
            if query.category and ev.category != query.category:
                continue
            if q:
                blob = f"{ev.who} {ev.target} {ev.request_id} {ev.category} {ev.error}".lower()
                if q not in blob:
                    continue
            out.append(ev)
        return out

    def page(self, query: Query) -> tuple[list[AuditEvent], int | None]:
        matched = self.filter(query)
        start = max(query.cursor, 0)
        end = start + query.limit
        page = matched[start:end]
        next_cursor = end if end < len(matched) else None
        return page, next_cursor

    def summary(self, query: Query) -> dict:
        matched = self.filter(query)
        by_action = Counter(e.action for e in matched)
        by_space = Counter(e.space for e in matched if e.space != "—")
        by_mount = Counter(e.mount for e in matched if e.mount != "—")
        by_category = Counter(e.category for e in matched)
        allowed = sum(1 for e in matched if e.result == "allowed")
        denied = sum(1 for e in matched if e.result == "denied")
        return {
            "window": {"from": query.from_time, "to": query.to_time},
            "totals": {"allowed": allowed, "denied": denied, "events": len(matched)},
            "by_action": dict(by_action.most_common()),
            "by_space": dict(by_space.most_common()),
            "by_mount": dict(by_mount.most_common()),
            "by_category": dict(by_category.most_common()),
        }

    def export_jsonl(self, query: Query) -> str:
        matched = self.filter(query)
        return "\n".join(json.dumps(e.to_dict(), ensure_ascii=False) for e in matched) + (
            "\n" if matched else ""
        )

    def export_csv(self, query: Query) -> str:
        matched = self.filter(query)
        buf = io.StringIO()
        fields = [
            "id",
            "time",
            "who",
            "action",
            "target",
            "environment",
            "space",
            "agent",
            "mount",
            "category",
            "result",
            "error",
            "request_id",
        ]
        writer = csv.DictWriter(buf, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for e in matched:
            writer.writerow(e.to_dict())
        return buf.getvalue()


def cluster_publish_runs(
    events: Iterable[AuditEvent],
    *,
    cluster_seconds: int = 120,
) -> list[dict]:
    """Group gitops prompt/cert writes into synthetic publish sessions.

    Full GitHub run_id correlation needs the Actions API; on the vault VM we
    only have OpenBao audit, so we cluster by writer + time proximity.
    """
    writers = ("gitops-pipeline",)
    interesting = {
        "prompt.write",
        "prompt.delete",
        "prompt.undelete",
        "cert.write",
        "transit.sign",
    }
    # Work oldest → newest for clustering, then reverse the run list.
    ordered = sorted(
        (e for e in events if e.category in interesting and any(w in e.who for w in writers)),
        key=lambda e: e.time or "",
    )
    runs: list[dict] = []
    current: dict | None = None
    last_ts: datetime | None = None

    for ev in ordered:
        ts = _parse_time(ev.time)
        if current is None or last_ts is None or ts is None:
            current = _new_run(ev)
            runs.append(current)
            last_ts = ts
            _accumulate(current, ev)
            continue
        delta = (ts - last_ts).total_seconds() if ts and last_ts else 10**9
        if delta > cluster_seconds:
            current = _new_run(ev)
            runs.append(current)
        _accumulate(current, ev)
        last_ts = ts or last_ts

    runs.reverse()
    return runs


def _new_run(ev: AuditEvent) -> dict:
    return {
        "run_id": f"vault-cluster-{ev.id}",
        "started_at": ev.time,
        "ended_at": ev.time,
        "who": ev.who,
        "conclusion": "success" if ev.result == "allowed" else "failure",
        "published": [],
        "deleted": [],
        "cert_writes": [],
        "event_ids": [],
        "html_url": None,
        "note": "Synthetic cluster from OpenBao audit (no GitHub run_id on VM)",
    }


def _accumulate(run: dict, ev: AuditEvent) -> None:
    run["ended_at"] = ev.time
    run["event_ids"].append(ev.id)
    if ev.result == "denied":
        run["conclusion"] = "failure"
    path = ev.target
    if ev.category == "prompt.write" and path not in run["published"]:
        run["published"].append(path)
    if ev.category == "prompt.delete" and path not in run["deleted"]:
        run["deleted"].append(path)
    if ev.category == "cert.write" and path not in run["cert_writes"]:
        run["cert_writes"].append(path)
