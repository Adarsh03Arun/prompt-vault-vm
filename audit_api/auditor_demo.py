"""In-memory demo catalogue for the auditor review APIs (read-only)."""

from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from typing import Any


def _iso(hours_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(hours=hours_ago)).isoformat().replace("+00:00", "Z")


# Plain-language labels — no product/app brand names in the auditor UI.
_AGENTS: list[dict[str, Any]] = [
    {
        "space": "care-floor",
        "agent": "bedside_triage_assistant",
        "display_name": "Bedside triage assistant",
        "description": "Helps nurses triage bedside requests.",
        "current_version": 12,
        "versions": {
            "12": {
                "status": "live",
                "created_at": _iso(1),
                "created_by": "ci-publish",
                "note": "Current live version",
                "system_prompt": {
                    "text": (
                        "You are a bedside triage assistant for hospital nursing staff.\n"
                        "Ask concise clarifying questions, never invent vitals, and escalate "
                        "emergencies to a human clinician immediately.\n"
                        "Do not provide medication dosages."
                    )
                },
            },
            "11": {
                "status": "deprecated",
                "created_at": _iso(48),
                "deprecated_at": _iso(1.1),
                "deprecated_by": "ci-publish",
                "note": "Superseded by version 12",
                "system_prompt": {
                    "text": (
                        "You are a bedside triage assistant.\n"
                        "Collect symptoms and urgency. Version 11 — do not use for new sessions."
                    )
                },
            },
            "8": {
                "status": "destroyed",
                "created_at": _iso(400),
                "destroyed_at": _iso(24),
                "destroyed_by": "vault-admin",
                "note": "Removed after retention window",
                "system_prompt": None,
            },
        },
        "changes": [
            {
                "id": "chg-1",
                "at": _iso(1),
                "who": "ci-publish",
                "action": "published",
                "version": 12,
                "summary": "Published version 12 and set it live",
            },
            {
                "id": "chg-2",
                "at": _iso(1.05),
                "who": "ci-publish",
                "action": "deprecated",
                "version": 11,
                "summary": "Deprecated version 11 (replaced by 12)",
            },
            {
                "id": "chg-3",
                "at": _iso(24),
                "who": "vault-admin",
                "action": "destroyed",
                "version": 8,
                "summary": "Destroyed old version 8",
            },
        ],
    },
    {
        "space": "care-floor",
        "agent": "discharge_summary_assistant",
        "display_name": "Discharge summary assistant",
        "description": "Drafts discharge summaries for clinician review.",
        "current_version": 3,
        "versions": {
            "3": {
                "status": "live",
                "created_at": _iso(5),
                "created_by": "ci-publish",
                "note": "Current live version",
                "system_prompt": {
                    "text": (
                        "You draft discharge summaries from structured notes.\n"
                        "Use only provided facts. Flag missing sections. "
                        "A clinician must approve before the summary is final."
                    )
                },
            },
            "2": {
                "status": "deprecated",
                "created_at": _iso(120),
                "deprecated_at": _iso(5.1),
                "deprecated_by": "ci-publish",
                "note": "Superseded by version 3",
                "system_prompt": {
                    "text": "You draft discharge summaries. (Version 2 — deprecated.)"
                },
            },
        },
        "changes": [
            {
                "id": "chg-d1",
                "at": _iso(5),
                "who": "ci-publish",
                "action": "published",
                "version": 3,
                "summary": "Published version 3",
            },
            {
                "id": "chg-d2",
                "at": _iso(5.1),
                "who": "ci-publish",
                "action": "deprecated",
                "version": 2,
                "summary": "Deprecated version 2",
            },
        ],
    },
    {
        "space": "claims",
        "agent": "insurance_claims_helper",
        "display_name": "Insurance claims helper",
        "description": "Assists staff with insurance claim wording checks.",
        "current_version": 7,
        "versions": {
            "7": {
                "status": "live",
                "created_at": _iso(10),
                "created_by": "ci-publish",
                "system_prompt": {
                    "text": (
                        "You help hospital billing staff check claim narratives for completeness.\n"
                        "Do not invent diagnosis codes. Suggest missing fields only."
                    )
                },
            },
            "6": {
                "status": "deprecated",
                "created_at": _iso(200),
                "deprecated_at": _iso(10.2),
                "deprecated_by": "release-manager",
                "system_prompt": {
                    "text": "Claims helper v6 (deprecated)."
                },
            },
        },
        "changes": [
            {
                "id": "chg-c1",
                "at": _iso(10),
                "who": "ci-publish",
                "action": "published",
                "version": 7,
                "summary": "Published version 7",
            },
            {
                "id": "chg-c2",
                "at": _iso(10.2),
                "who": "release-manager",
                "action": "deprecated",
                "version": 6,
                "summary": "Deprecated version 6",
            },
        ],
    },
    {
        "space": "care-floor",
        "agent": "legacy_scribe",
        "display_name": "Legacy scribe (retired)",
        "description": "Soft-deleted — not available to runtimes.",
        "current_version": None,
        "soft_deleted": True,
        "versions": {
            "1": {
                "status": "soft_deleted",
                "created_at": _iso(800),
                "soft_deleted_at": _iso(30),
                "soft_deleted_by": "space-owner",
                "system_prompt": {
                    "text": "Retired scribe agent. Do not use."
                },
            },
        },
        "changes": [
            {
                "id": "chg-s1",
                "at": _iso(30),
                "who": "space-owner",
                "action": "soft_deleted",
                "version": 1,
                "summary": "Agent soft-deleted (kill switch)",
            },
        ],
    },
]


def list_agents(*, space: str | None = None, q: str | None = None) -> list[dict[str, Any]]:
    qn = (q or "").strip().lower()
    out = []
    for a in _AGENTS:
        if space and a["space"] != space:
            continue
        blob = f"{a['space']} {a['agent']} {a['display_name']} {a.get('description','')}".lower()
        if qn and qn not in blob:
            continue
        out.append(
            {
                "space": a["space"],
                "agent": a["agent"],
                "display_name": a["display_name"],
                "description": a.get("description", ""),
                "current_version": a.get("current_version"),
                "soft_deleted": bool(a.get("soft_deleted")),
                "version_count": len(a.get("versions") or {}),
            }
        )
    return out


def get_agent(space: str, agent: str) -> dict[str, Any] | None:
    for a in _AGENTS:
        if a["space"] == space and a["agent"] == agent:
            return {
                "space": a["space"],
                "agent": a["agent"],
                "display_name": a["display_name"],
                "description": a.get("description", ""),
                "current_version": a.get("current_version"),
                "soft_deleted": bool(a.get("soft_deleted")),
            }
    return None


def list_versions(space: str, agent: str) -> list[dict[str, Any]] | None:
    for a in _AGENTS:
        if a["space"] == space and a["agent"] == agent:
            rows = []
            for ver, meta in a["versions"].items():
                rows.append(
                    {
                        "version": int(ver),
                        "status": meta["status"],
                        "created_at": meta.get("created_at"),
                        "deprecated_at": meta.get("deprecated_at"),
                        "destroyed_at": meta.get("destroyed_at"),
                        "soft_deleted_at": meta.get("soft_deleted_at"),
                        "note": meta.get("note", ""),
                        "is_current": a.get("current_version") == int(ver),
                        "has_prompt": meta.get("system_prompt") is not None,
                    }
                )
            rows.sort(key=lambda r: r["version"], reverse=True)
            return rows
    return None


def get_prompt(space: str, agent: str, version: int | None) -> dict[str, Any] | None:
    for a in _AGENTS:
        if a["space"] != space or a["agent"] != agent:
            continue
        ver = version if version is not None else a.get("current_version")
        if ver is None:
            return None
        meta = a["versions"].get(str(ver))
        if not meta:
            return None
        if meta.get("system_prompt") is None:
            return {
                "space": space,
                "agent": agent,
                "display_name": a["display_name"],
                "version": int(ver),
                "status": meta["status"],
                "system_prompt": None,
                "unavailable_reason": "This version was destroyed or has no stored prompt text.",
            }
        return {
            "space": space,
            "agent": agent,
            "display_name": a["display_name"],
            "version": int(ver),
            "status": meta["status"],
            "is_current": a.get("current_version") == int(ver),
            "system_prompt": deepcopy(meta["system_prompt"]),
        }
    return None


def list_changes(space: str, agent: str) -> list[dict[str, Any]] | None:
    for a in _AGENTS:
        if a["space"] == space and a["agent"] == agent:
            return list(a.get("changes") or [])
    return None


def list_spaces() -> list[str]:
    return sorted({a["space"] for a in _AGENTS})
