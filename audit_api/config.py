from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    """Runtime config for the audit API on the Prompt Vault VM."""

    audit_log_path: str
    api_token: str
    host: str = "0.0.0.0"
    port: int = 8088
    max_scan_lines: int = 500_000
    default_limit: int = 200
    max_limit: int = 2000
    # How tightly to cluster gitops writes into a synthetic "publish run"
    publish_cluster_seconds: int = 120

    @classmethod
    def from_env(cls) -> "Settings":
        path = os.environ.get("OPENBAO_AUDIT_LOG_PATH", "").strip()
        if not path:
            raise SystemExit("Set OPENBAO_AUDIT_LOG_PATH to the OpenBao audit file on this VM")
        token = os.environ.get("AUDIT_API_TOKEN", "").strip()
        if not token:
            raise SystemExit("Set AUDIT_API_TOKEN (bearer token for internal dashboard callers)")
        return cls(
            audit_log_path=path,
            api_token=token,
            host=os.environ.get("AUDIT_API_HOST", "0.0.0.0").strip() or "0.0.0.0",
            port=int(os.environ.get("AUDIT_API_PORT", "8088")),
            max_scan_lines=int(os.environ.get("AUDIT_API_MAX_SCAN_LINES", "500000")),
            default_limit=int(os.environ.get("AUDIT_API_DEFAULT_LIMIT", "200")),
            max_limit=int(os.environ.get("AUDIT_API_MAX_LIMIT", "2000")),
            publish_cluster_seconds=int(os.environ.get("AUDIT_API_PUBLISH_CLUSTER_SECONDS", "120")),
        )
