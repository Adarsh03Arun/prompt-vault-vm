"""Normalize OpenBao audit JSONL (response events only)."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass
from typing import Any

PROMPT_PATH = re.compile(
    r"^secret/(?:data|metadata)/prompts/(?P<env>[^/]+)(?:/(?P<space>[^/]+))?(?:/(?P<agent>[^/]+))?"
)
CERT_PATH = re.compile(r"^secret/data/agent-certs/(?P<env>[^/]+)/(?P<space>[^/]+)")
AUTH_PATH = re.compile(r"^auth/(?P<mount>[^/]+)/login")


@dataclass(frozen=True)
class AuditEvent:
    id: str
    time: str
    who: str
    entity_id: str
    action: str
    target: str
    environment: str
    space: str
    agent: str
    mount: str
    category: str
    result: str  # allowed | denied
    error: str
    request_id: str
    source: str = "openbao-audit"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_l1(self) -> dict[str, Any]:
        return {
            "time": self.time,
            "who": self.who,
            "action": self.action,
            "target": self.target,
            "environment": self.environment,
            "result": self.result,
        }


def _stable_id(time: str, request_id: str, path: str, who: str) -> str:
    raw = f"{time}|{request_id}|{path}|{who}"
    return "oba-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:20]


def classify(
    *,
    path: str,
    action: str,
    who: str,
) -> tuple[str, str, str, str, str]:
    """Return (category, environment, space, agent, mount)."""
    auth = AUTH_PATH.match(path or "")
    if auth:
        mount = f"auth/{auth.group('mount')}"
        m = auth.group("mount")
        if m == "cert":
            cat = "auth.cert.login"
        elif m == "approle":
            cat = "auth.approle.login"
        elif m in ("jwt", "jwt-github"):
            cat = "auth.jwt.login"
        elif m == "github":
            cat = "auth.github.login"
        else:
            cat = f"auth.{m}.login"
        return cat, "—", "—", "—", mount

    cert = CERT_PATH.match(path or "")
    if cert:
        op = "cert.write" if action in ("create", "update") else "cert.read"
        return op, cert.group("env"), cert.group("space"), "—", "secret"

    prompt = PROMPT_PATH.match(path or "")
    if prompt:
        env = prompt.group("env") or "—"
        space = prompt.group("space") or "—"
        agent = prompt.group("agent") or "—"
        if action == "list" or (space != "—" and agent == "—"):
            cat = "prompt.list"
        elif "/metadata/" in path and action in ("create", "update", "patch"):
            cat = "prompt.metadata"
        elif action in ("create", "update"):
            cat = "prompt.write"
        elif action in ("delete", "destroy"):
            cat = "prompt.delete"
        elif action == "undelete":
            cat = "prompt.undelete"
        elif "metadata" in path:
            cat = "prompt.metadata"
        else:
            cat = "prompt.read"
        return cat, env, space, agent, "secret"

    if path.startswith("transit/"):
        return "transit.sign" if "sign" in path else "transit", "—", "—", "—", "transit"

    return "other", "—", "—", "—", "—"


def parse_line(line: str) -> AuditEvent | None:
    line = line.strip()
    if not line:
        return None
    try:
        entry = json.loads(line)
    except json.JSONDecodeError:
        return None
    if entry.get("type") != "response":
        return None

    req = entry.get("request") or {}
    auth = entry.get("auth") or {}
    path = req.get("path") or "unknown"
    action = req.get("operation") or "unknown"
    who = auth.get("display_name") or auth.get("meta", {}).get("role_name") or "unknown"
    entity_id = auth.get("entity_id") or ""
    request_id = req.get("id") or entry.get("request_id") or ""
    err = entry.get("error") or ""
    result = "denied" if err else "allowed"
    time = entry.get("time") or ""

    category, environment, space, agent, mount = classify(path=path, action=action, who=who)
    if result == "denied" and category.startswith("auth."):
        category = "policy.denied"
    elif result == "denied" and category.startswith("prompt."):
        # keep prompt.* but callers can filter result=denied; also tag policy
        pass

    return AuditEvent(
        id=_stable_id(time, request_id, path, who),
        time=time,
        who=who,
        entity_id=entity_id,
        action=action,
        target=path,
        environment=environment,
        space=space,
        agent=agent,
        mount=mount,
        category=category if result == "allowed" else (
            "policy.denied" if category.startswith("auth.") else category
        ),
        result=result,
        error=str(err) if err else "",
        request_id=request_id,
    )
