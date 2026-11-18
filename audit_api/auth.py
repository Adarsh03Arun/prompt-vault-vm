from __future__ import annotations

import secrets

from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings

_bearer = HTTPBearer(auto_error=False)


def build_auth_dependency(settings_provider):
    """Return a FastAPI dependency that checks Authorization: Bearer <token>."""

    def verify(
        creds: HTTPAuthorizationCredentials | None = Security(_bearer),
    ) -> None:
        settings: Settings = settings_provider()
        if creds is None or creds.scheme.lower() != "bearer":
            raise HTTPException(status_code=401, detail="Missing bearer token")
        if not secrets.compare_digest(creds.credentials, settings.api_token):
            raise HTTPException(status_code=401, detail="Invalid bearer token")

    return Depends(verify)
