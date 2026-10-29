#!/usr/bin/env python3
"""GitOps writer — the sole path that writes new prompt versions into
OpenBao, per docs/design/openbao-architecture-and-integration.md §3.8 and
the draft KV v2 data shape in
docs/design/prompt-vault-technical-design-keycloak-openbao.md §5.1
(*status: draft, open to discussion* — this script implements that draft
as written so the round trip is testable now; expect field names here to
move if that draft changes).

Reads
enterprise_agent_platform/prompts/<space>/<agent_name>/{system_prompt.md,meta.yaml},
authenticates to OpenBao via the gitops-pipeline AppRole (see
../openbao/policies/gitops-pipeline-write.hcl), signs each prompt's content
with the vault's own vault-signing Transit key, and writes one new KV v2
version per agent.

Never reads anything back. After writing the versioned secret it PATCHes
custom_metadata with the content-descriptive fields from meta.yaml (space,
agent_name, owning_team, risk_tier, version, model). It does not set
status / active_version — flipping a version live is a human-approval
action (Admin UI). PATCH merges, so a republish does not wipe those
human keys. gitops-pipeline-write.hcl grants metadata patch only, not
read or a full metadata replace.

Usage:
  OPENBAO_ROLE_ID=... OPENBAO_SECRET_ID=... python publish_prompts.py \\
      --url https://openbao.internal:8200 --environment prod \\
      --author "$(git log -1 --format=%ae)" \\
      --change-summary "$(git log -1 --format=%s)"
"""

from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path

import hvac
import yaml

_SCRIPT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRIPT_DIR.parents[3]  # .../tch
PROMPTS_ROOT = _REPO_ROOT / "enterprise_agent_platform" / "prompts"

sys.path.insert(0, str(_REPO_ROOT))
from enterprise_agent_platform.infra.prompt_vault import OpenBaoPromptVault  # noqa: E402


def iter_agent_dirs(prompts_root: Path):
    for space_dir in sorted(p for p in prompts_root.iterdir() if p.is_dir()):
        for agent_dir in sorted(p for p in space_dir.iterdir() if p.is_dir()):
            yield space_dir.name, agent_dir.name, agent_dir



# Maintain consistency accordingly with respect to data mapper of OpenBao
"""Cross-checks the directory-encoded space against the adapter's own
mapping, so the content layout and OpenBaoPromptVault.DEFAULT_AGENT_SPACES
can't silently drift apart without either side noticing."""
def check_space_consistency(space: str, agent_name: str) -> None:
    expected = OpenBaoPromptVault.DEFAULT_AGENT_SPACES.get(agent_name)
    if expected is not None and expected != space:
        raise ValueError(
            f"{agent_name}: prompts/{space}/... does not match "
            f"OpenBaoPromptVault.DEFAULT_AGENT_SPACES[{agent_name!r}] = {expected!r}. "
            "Fix one of the two before publishing."
        )


def login(client: hvac.Client, role_id: str, secret_id: str) -> None:
    client.auth.approle.login(role_id=role_id, secret_id=secret_id)


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sign(client: hvac.Client, system_prompt: dict) -> dict:
    encoded = base64.b64encode(canonical_json_bytes(system_prompt)).decode("ascii")
    result = client.secrets.transit.sign_data(name="vault-signing", hash_input=encoded)
    return {"key": "vault-signing", "value": result["data"]["signature"]}


def build_custom_metadata(*, space: str, agent_name: str, agent_dir: Path, version: int) -> dict[str, str]:
    """Flat string map for KV v2 custom_metadata. No status / active_version.

    `version` is the real KV v2 version OpenBao just assigned on write
    (see publish_one) - not a manually-maintained meta.yaml field. A
    hand-edited version number can't actually track OpenBao's own
    version counter (every meta.yaml in this repo was still "version: 1"
    despite having been published repeatedly in testing - confirmed
    stale, not hypothetical), so it isn't trusted as a source of truth
    anymore.
    """
    meta = yaml.safe_load((agent_dir / "meta.yaml").read_text(encoding="utf-8")) or {}
    fields = {
        "space": space,
        "agent_name": agent_name,
        "version": str(version),
        "model": meta.get("model"),
        "owning_team": meta.get("owning_team"),
        "risk_tier": meta.get("risk_tier"),
    }
    return {key: str(value) for key, value in fields.items() if value is not None}


def write_custom_metadata(client: hvac.Client, *, path: str, custom_metadata: dict[str, str]) -> None:
    # merge-patch so GitOps keys overlay without replacing status/active_version.
    # Do not use hvac update_metadata: it POSTs a full replace and defaults
    # delete_version_after to "0s", which would drop the 5y retention.
    client.adapter.request(
        "PATCH",
        f"/v1/secret/metadata/{path}",
        headers={"Content-Type": "application/merge-patch+json"},
        data=json.dumps({"custom_metadata": custom_metadata}),
    )


def build_payload(client: hvac.Client, *, agent_dir: Path, author: str, change_summary: str) -> dict:
    prompt_text = (agent_dir / "system_prompt.md").read_text(encoding="utf-8").strip()
    meta = yaml.safe_load((agent_dir / "meta.yaml").read_text(encoding="utf-8")) or {}
    # system_prompt is a JSON object, {"text": ...} - not a bare string.
    # Lets this grow additional structured fields later without a
    # breaking shape change, and is what Transit actually signs below.
    system_prompt = {"text": prompt_text}
    prompt_bytes = canonical_json_bytes(system_prompt)
    return {
        "system_prompt": system_prompt,
        "model": meta["model"],
        "author": author,
        "change_summary": change_summary,
        "content_sha256": hashlib.sha256(prompt_bytes).hexdigest(),
        "signature": sign(client, system_prompt),
        "test_gate": meta.get("test_gate"),
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    }


def publish_one(client: hvac.Client, *, environment: str, space: str, agent_name: str,
                 agent_dir: Path, author: str, change_summary: str) -> str:
    check_space_consistency(space, agent_name)
    payload = build_payload(client, agent_dir=agent_dir, author=author, change_summary=change_summary)
    path = f"prompts/{environment}/{space}/{agent_name}"
    response = client.secrets.kv.v2.create_or_update_secret(path=path, secret=payload, mount_point="secret")
    # The real version KV v2 just assigned - not a hand-maintained
    # meta.yaml field, which can't actually stay in sync with it.
    version = response["data"]["version"]
    write_custom_metadata(
        client,
        path=path,
        custom_metadata=build_custom_metadata(space=space, agent_name=agent_name, agent_dir=agent_dir, version=version),
    )
    return path


def publish_all(client: hvac.Client, *, environment: str, author: str, change_summary: str,
                 prompts_root: Path = PROMPTS_ROOT) -> list[str]:
    published = []
    for space, agent_name, agent_dir in iter_agent_dirs(prompts_root):
        path = publish_one(
            client,
            environment=environment,
            space=space,
            agent_name=agent_name,
            agent_dir=agent_dir,
            author=author,
            change_summary=change_summary,
        )
        published.append(path)
    return published


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--author", required=True)
    parser.add_argument("--change-summary", required=True)
    parser.add_argument("--prompts-root", default=str(PROMPTS_ROOT))
    args = parser.parse_args(argv)

    role_id = os.environ["OPENBAO_ROLE_ID"]
    secret_id = os.environ["OPENBAO_SECRET_ID"]

    client = hvac.Client(url=args.url)
    login(client, role_id, secret_id)

    published = publish_all(
        client,
        environment=args.environment,
        author=args.author,
        change_summary=args.change_summary,
        prompts_root=Path(args.prompts_root),
    )
    for path in published:
        print(f"published {path}")
    print(f"done - {len(published)} prompt(s) published")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
