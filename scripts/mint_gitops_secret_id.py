#!/usr/bin/env python3
"""CI secret_id broker — GitHub OIDC JWT in, one-time AppRole secret_id out.

Closes the gap documented in CONTEXT.md / .github/workflows/publish-prompts.yaml:
the gitops-pipeline AppRole is provisioned with secret_id_num_uses=1, so a
static OPENBAO_SECRET_ID GitHub secret is spent on the first run. This
script is the per-run mint: it logs into the jwt-github mount (a second
JWT backend — auth/jwt is already Keycloak's, and OpenBao allows only one
issuer per mount; see https://openbao.org/docs/auth/jwt/) with the
workflow's GitHub OIDC token, then calls
auth/approle/role/gitops-pipeline/secret-id.

The resulting OpenBao token is bound to gitops-secret-id-mint.hcl, which
can mint that one secret_id and nothing else — it cannot write prompts.
publish_prompts.py still authenticates via AppRole as the sole writer
(architecture doc §3.8).

Usage (from GitHub Actions, after fetching the OIDC token):
  GITHUB_OIDC_TOKEN=... python mint_gitops_secret_id.py \\
      --url https://openbao.internal:8200
  # stdout is the secret_id and nothing else — capture it, mask it,
  # pass it to publish_prompts.py as OPENBAO_SECRET_ID.
"""

from __future__ import annotations

import argparse
import os

import hvac

JWT_MOUNT = "jwt-github"
MINTER_ROLE = "gitops-secret-id-minter"
APPROLE_NAME = "gitops-pipeline"


def mint_secret_id(
    client: hvac.Client,
    jwt: str,
    *,
    role: str = MINTER_ROLE,
    jwt_path: str = JWT_MOUNT,
    approle_name: str = APPROLE_NAME,
) -> str:
    # hvac JWT.jwt_login path= defaults to "jwt" (the Keycloak mount). Must
    # be passed explicitly — see hvac 2.3 JWT.DEFAULT_PATH.
    # Source: https://github.com/hvac/hvac/blob/v2.3.0/hvac/api/auth_methods/jwt.py
    client.auth.jwt.jwt_login(role=role, jwt=jwt, path=jwt_path)
    resp = client.auth.approle.generate_secret_id(role_name=approle_name)
    return resp["data"]["secret_id"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    args = parser.parse_args(argv)

    jwt = os.environ["GITHUB_OIDC_TOKEN"]
    client = hvac.Client(url=args.url)
    # Print the secret_id alone so the caller can capture stdout without
    # scraping. Never echo the JWT — it is a short-lived credential.
    print(mint_secret_id(client, jwt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
