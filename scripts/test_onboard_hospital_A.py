#!/usr/bin/env python3
"""Create/verify Keycloak realm hospital-A (test onboard)."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERSONAS = json.loads((ROOT / "keycloak/hospital-onboarding/personas.json").read_text(encoding="utf-8"))


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip().strip('"').strip("'")
        out[k.strip()] = v
    return out


def http_json(method: str, url: str, token: str | None = None, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw.decode()) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        raise SystemExit(f"{method} {url} -> HTTP {e.code}: {raw[:500]}") from e


def main() -> None:
    env_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "keycloak/hospital-onboarding/hospital-A.local.env"
    if not env_path.is_file():
        env_path = ROOT / "keycloak/hospital-onboarding/hospital-A.env"
    env = load_env(env_path)
    env.update({k: v for k, v in os.environ.items() if k.startswith(("KC_", "HOSPITAL_", "LOGIN_", "RACC_", "POD_"))})

    base = env["KC_URL"].rstrip("/")
    password = env.get("KC_ADMIN_PASSWORD", "REPLACE_ME")
    if password in ("", "REPLACE_ME"):
        raise SystemExit(f"Set KC_ADMIN_PASSWORD in {env_path}")

    slug = env.get("HOSPITAL_SLUG", "A")
    realm = f"hospital-{slug}"
    display = env.get("HOSPITAL_DISPLAY_NAME", "Hospital A")
    theme = env.get("LOGIN_THEME", "xelerait")
    logo = env.get("LOGIN_LOGO_URL", "")

    print("==> Admin token")
    form = urllib.parse.urlencode(
        {
            "client_id": "admin-cli",
            "username": env.get("KC_ADMIN_USER", "kc-admin"),
            "password": password,
            "grant_type": "password",
        }
    ).encode()
    req = urllib.request.Request(f"{base}/realms/master/protocol/openid-connect/token", data=form, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=60) as resp:
        token = json.loads(resp.read().decode())["access_token"]

    print(f"==> Realm {realm}")
    try:
        _, existing = http_json("GET", f"{base}/admin/realms/{realm}", token)
        print("    exists — updating")
        assert isinstance(existing, dict)
        existing["displayName"] = display
        existing["loginTheme"] = theme
        attrs = dict(existing.get("attributes") or {})
        if logo:
            attrs["loginLogoUrl"] = logo
        existing["attributes"] = attrs
        http_json("PUT", f"{base}/admin/realms/{realm}", token, existing)
    except SystemExit as e:
        if "404" not in str(e):
            raise
        print("    creating")
        body = {
            "realm": realm,
            "displayName": display,
            "enabled": True,
            "sslRequired": env.get("SSL_REQUIRED", "none"),
            "registrationAllowed": False,
            "loginTheme": theme,
            "attributes": {"loginLogoUrl": logo} if logo else {},
        }
        http_json("POST", f"{base}/admin/realms", token, body)

    def upsert_client(cid: str, root: str, redirects: str, origins: str, enabled: bool) -> str:
        _, clients = http_json("GET", f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(cid)}", token)
        payload = {
            "clientId": cid,
            "name": cid,
            "enabled": enabled,
            "publicClient": True,
            "standardFlowEnabled": True,
            "directAccessGrantsEnabled": False,
            "rootUrl": root,
            "redirectUris": redirects.split(),
            "webOrigins": origins.split(),
            "attributes": {"pkce.code.challenge.method": "S256"},
        }
        if clients:
            uuid = clients[0]["id"]
            print(f"    client {cid} — update")
            http_json("PUT", f"{base}/admin/realms/{realm}/clients/{uuid}", token, payload)
            return uuid
        print(f"    client {cid} — create")
        # create returns 201 empty; re-fetch uuid
        try:
            http_json("POST", f"{base}/admin/realms/{realm}/clients", token, payload)
        except SystemExit as e:
            if "201" not in str(e) and "409" not in str(e):
                # urllib raises on non-2xx; 201 is success — handle via raw request
                pass
            else:
                raise
        _, clients = http_json("GET", f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(cid)}", token)
        return clients[0]["id"]

    # Fix create: urllib treats 201 as success
    def post_client(payload: dict) -> None:
        data = json.dumps(payload).encode()
        req = urllib.request.Request(f"{base}/admin/realms/{realm}/clients", data=data, method="POST")
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=60) as resp:
            if resp.status not in (201, 204, 200):
                raise SystemExit(f"create client failed: {resp.status}")

    print("==> Clients")
    def upsert_client2(cid: str, root: str, redirects: str, origins: str, enabled: bool) -> str:
        _, clients = http_json("GET", f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(cid)}", token)
        payload = {
            "clientId": cid,
            "name": cid,
            "enabled": enabled,
            "publicClient": True,
            "standardFlowEnabled": True,
            "directAccessGrantsEnabled": False,
            "rootUrl": root,
            "redirectUris": redirects.split(),
            "webOrigins": origins.split(),
            "attributes": {"pkce.code.challenge.method": "S256"},
        }
        if clients:
            uuid = clients[0]["id"]
            print(f"    client {cid} — update")
            http_json("PUT", f"{base}/admin/realms/{realm}/clients/{uuid}", token, payload)
            return uuid
        print(f"    client {cid} — create")
        post_client(payload)
        _, clients = http_json("GET", f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(cid)}", token)
        return clients[0]["id"]

    racc_uuid = upsert_client2(
        env.get("RACC_CLIENT_ID", "racc"),
        env.get("RACC_ROOT_URL", "http://localhost:3000"),
        env.get("RACC_REDIRECT_URIS", "http://localhost:3000/*"),
        env.get("RACC_WEB_ORIGINS", "http://localhost:3000"),
        True,
    )
    upsert_client2(
        env.get("POD_CLIENT_ID", "pod"),
        env.get("POD_ROOT_URL", "http://localhost:3001"),
        env.get("POD_REDIRECT_URIS", "http://localhost:3001/*"),
        env.get("POD_WEB_ORIGINS", "http://localhost:3001"),
        env.get("POD_ENABLED", "false").lower() == "true",
    )

    print("==> Persona roles")
    for p in PERSONAS["personas"]:
        role = f"persona-{p['key']}"
        try:
            http_json("GET", f"{base}/admin/realms/{realm}/clients/{racc_uuid}/roles/{urllib.parse.quote(role)}", token)
            print(f"    {role} exists")
        except SystemExit as e:
            if "404" not in str(e):
                raise
            print(f"    {role} create")
            data = json.dumps({"name": role, "description": p["label"]}).encode()
            req = urllib.request.Request(
                f"{base}/admin/realms/{realm}/clients/{racc_uuid}/roles",
                data=data,
                method="POST",
            )
            req.add_header("Authorization", f"Bearer {token}")
            req.add_header("Content-Type", "application/json")
            with urllib.request.urlopen(req, timeout=60) as resp:
                assert resp.status in (201, 204, 200)

    _, realm_info = http_json("GET", f"{base}/admin/realms/{realm}", token)
    _, roles = http_json("GET", f"{base}/admin/realms/{realm}/clients/{racc_uuid}/roles", token)
    persona_roles = sorted(r["name"] for r in roles if r["name"].startswith("persona-"))
    print("==> Verify")
    print(json.dumps({"realm": realm_info["realm"], "displayName": realm_info.get("displayName"), "loginTheme": realm_info.get("loginTheme"), "personaRoles": len(persona_roles)}, indent=2))
    print("\n".join(persona_roles))
    print(f"\nLogin preview: {base}/realms/{realm}/account/")


if __name__ == "__main__":
    main()
