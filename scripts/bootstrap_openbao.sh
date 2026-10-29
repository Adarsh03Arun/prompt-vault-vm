#!/usr/bin/env bash
set -euo pipefail

# Idempotent OpenBao bootstrap - run against a freshly unsealed server with
# an authenticated root/admin bao CLI session.
#
# Reads spaces.yaml so adding a space is a data change here, never a script
# change (agent-agnostic by construction - see ../CONTEXT.md).
#
# Requires: bao CLI, yq, jq.
#
# Env vars:
#   KILL_SWITCH_AUTH_MODE     undecided (default) | break_glass_cert | keycloak_gated
#   AGENT_AUTH_METHOD         cert (default, implemented) | spiffe (stubbed)
#   AGENT_CA_CERT_PATH        path to the CA PEM trusted for agent-cert-auth (required if AGENT_AUTH_METHOD=cert)
#   AGENT_ALLOWED_COMMON_NAMES glob for allowed agent cert CNs (default: *.agents.internal)
#   GITHUB_OIDC_BOUND_REPOSITORY  owner/repo that may mint gitops-pipeline secret_ids
#                                 (unset: skip jwt-github; AppRole still created)
#   GITHUB_OIDC_BOUND_AUDIENCE    aud claim the workflow must request (default: openbao)
#   KEYCLOAK_OIDC_HOST            Keycloak host OpenBao itself reaches for OIDC discovery/JWKS
#                                 (unset: skip writing auth/jwt config; roles still rendered)
#   KEYCLOAK_ISSUER_HOST          Keycloak host that actually ends up in a real token's "iss"
#                                 claim - i.e. where a human's browser/the Admin UI backend
#                                 reaches Keycloak, which can differ from KEYCLOAK_OIDC_HOST
#                                 (e.g. Docker Compose: OpenBao reaches "keycloak:8080"
#                                 internally, but a human reaches "localhost:8081" - using
#                                 one host for both broke real login with "invalid issuer (iss)
#                                 claim", 2026-10-27). Defaults to KEYCLOAK_OIDC_HOST.
#   KEYCLOAK_REALM_TOPOLOGY       shared (default) | dedicated   — see ../keycloak/README.md
#   KEYCLOAK_REALM_NAME           default: tch
#   KEYCLOAK_CLIENT_ID            default: prompt-vault-admin-ui
#   KEYCLOAK_ROLE_SOURCE          client (default, resource_access) | realm (realm_access)
#   PROMPT_RETENTION_PERIOD       how long an old prompt version stays readable after being
#                                 superseded, as an OpenBao duration string (default: 43800h,
#                                 ~5 years - resolved 2026-10-27, no number had been picked
#                                 before this; genuinely still open: whether 5 years is the
#                                 right number long-term needs compliance input - see
#                                 ../CONTEXT.md). "0s" means never auto-delete.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPACES_FILE="$ROOT/spaces.yaml"
KILL_SWITCH_MODE="${KILL_SWITCH_AUTH_MODE:-undecided}"
AGENT_AUTH_METHOD="${AGENT_AUTH_METHOD:-cert}"
# openbao-pki (default): rotation is automated - see
# scripts/pki/rotate_leaf_cert.sh and scripts/pki/README.md. manual: the
# old path, an externally-issued CA PEM via AGENT_CA_CERT_PATH /
# ONCALL_CA_CERT_PATH (scripts/pki/generate_ca.sh), kept for whoever isn't
# ready to depend on OpenBao's own PKI engine yet.
CERT_ROTATION_MODE="${CERT_ROTATION_MODE:-openbao-pki}"

# Enables a PKI secrets engine mount as a root CA (idempotent) and writes
# one role on it. Used for the agent and on-call client CAs ONLY - never
# the server TLS CA, which has to exist before OpenBao is reachable at
# all and so structurally can't depend on OpenBao itself (see
# scripts/pki/README.md's "natural upgrade path" note).
ensure_pki_ca() {
  local mount="$1" role="$2" domain="$3" common_name="$4" ttl="$5" max_ttl="$6"
  bao secrets enable -path="$mount" pki || true
  bao secrets tune -max-lease-ttl="$max_ttl" "$mount" >/dev/null
  if ! bao read "${mount}/cert/ca" >/dev/null 2>&1; then
    bao write -field=certificate "${mount}/root/generate/internal" \
      common_name="$common_name" ttl="$max_ttl" > /dev/null
  fi
  bao write "${mount}/roles/${role}" \
    allowed_domains="$domain" allow_subdomains=true allow_bare_domains=true \
    client_flag=true server_flag=false key_usage="DigitalSignature" \
    ttl="$ttl" max_ttl="$ttl" > /dev/null
}

echo "==> Enabling secrets engines"
bao secrets enable -path=secret -version=2 kv || true
bao secrets enable transit || true

echo "==> Retention: ${PROMPT_RETENTION_PERIOD:-43800h} (prompt versions auto-delete after this long once superseded)"
bao write secret/config delete_version_after="${PROMPT_RETENTION_PERIOD:-43800h}" max_versions=0

echo "==> Per-space Transit keys + Identity Groups (from spaces.yaml - adding a space here needs no script change)"
# The Identity Group is purely organizational/browsable (resolved
# 2026-10-27) - it does NOT carry a policy and does not change how access
# is actually decided; that stays the existing space-agnostic
# agent-prompt-read.hcl templated off each entity's own metadata.space.
# Before this, a space had no object of its own in OpenBao at all - only
# a metadata value on whichever entities happened to carry it, which is
# genuinely invisible until you go read a specific entity. `identity/group`
# write with just `name=` is idempotent by name (confirmed against a real
# server: writing it twice updates the same group, not a duplicate).
yq -r '.spaces[].name' "$SPACES_FILE" | while read -r space; do
  bao write -f "transit/keys/space-${space}" type=aes256-gcm96 || true
  bao write identity/group name="$space" type=internal > /dev/null
done

echo "==> Vault's own signing key (FR-10 - signs approved content on write)"
bao write -f transit/keys/vault-signing type=ed25519 || true

echo "==> Agent ACL policy (space-agnostic, identity-metadata templated)"
bao policy write agent-prompt-read "$ROOT/openbao/policies/agent-prompt-read.hcl"

echo "==> Human admin-ui policies - all 8 personas (resolved 2026-10-27, see ../CONTEXT.md)"
# Each persona gets its own distinctly-named OpenBao policy, so the audit
# log shows which kind of persona acted - but the underlying capability
# content comes from one of three proven tiers (read-only / review-release
# / admin), not 8 independently-written files. See vault-viewer.hcl's and
# vault-approver.hcl's own top comments for exactly which personas share
# which tier and why.
bao policy write prompt-author     "$ROOT/openbao/policies/vault-viewer.hcl"
bao policy write security-officer  "$ROOT/openbao/policies/vault-viewer.hcl"
bao policy write auditor           "$ROOT/openbao/policies/vault-viewer.hcl"
bao policy write domain-reviewer   "$ROOT/openbao/policies/vault-approver.hcl"
bao policy write technical-reviewer "$ROOT/openbao/policies/vault-approver.hcl"
bao policy write release-manager   "$ROOT/openbao/policies/vault-approver.hcl"
bao policy write space-owner       "$ROOT/openbao/policies/vault-approver.hcl"
bao policy write vault-admin       "$ROOT/openbao/policies/vault-admin.hcl"
# security-officer's real kill-switch capability does NOT come from this
# policy or from Keycloak at all - it comes from being issued a
# break-glass certificate (scripts/register_oncall_identity.sh), on a
# separate CA, deliberately independent of Keycloak so the kill switch
# still works if Keycloak itself is down or compromised. This persona's
# Keycloak-side policy is read-only, same as prompt-author/auditor -
# confirmed this is the intended shape, not an oversight, 2026-10-27.

echo "==> auth/jwt against Keycloak (human admin-UI path)"
KEYCLOAK_REALM_TOPOLOGY="${KEYCLOAK_REALM_TOPOLOGY:-shared}"
KEYCLOAK_REALM_NAME="${KEYCLOAK_REALM_NAME:-tch}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-prompt-vault-admin-ui}"
KEYCLOAK_ROLE_SOURCE="${KEYCLOAK_ROLE_SOURCE:-client}"
if [ "$KEYCLOAK_REALM_TOPOLOGY" = "shared" ] && [ "$KEYCLOAK_ROLE_SOURCE" = "realm" ]; then
  echo "    WARNING: shared topology with KEYCLOAK_ROLE_SOURCE=realm collides with other backends. Use client roles (the default), or switch topology to dedicated." >&2
fi
if [ "$KEYCLOAK_REALM_TOPOLOGY" = "dedicated" ] && [ "$KEYCLOAK_REALM_NAME" = "tch" ]; then
  echo "    WARNING: dedicated topology still using the shared default realm name. Set KEYCLOAK_REALM_NAME to a workstream-specific realm (suggested: prompt-vault)." >&2
fi
bao auth enable jwt || true
# https by default (every VM-SETUP.md deployment fronts Keycloak with TLS
# somewhere, even though direct TLS on Keycloak itself is optional unlike
# OpenBao - see openbao/VM-SETUP.md §1). KEYCLOAK_OIDC_SCHEME=http exists
# for exactly one real case: a local Docker Compose dev run
# (deploy/identity-vault/docker/) where Keycloak speaks plain HTTP and
# there is no fronting TLS at all - hardcoding https unconditionally
# broke OIDC discovery against a real server in that case ("error
# checking oidc discovery URL", 2026-10-27).
KEYCLOAK_OIDC_SCHEME="${KEYCLOAK_OIDC_SCHEME:-https}"
# KEYCLOAK_OIDC_HOST is where OpenBao itself reaches Keycloak to fetch
# OIDC discovery/JWKS - from OpenBao's OWN network vantage point. That is
# NOT necessarily the same place a human's browser (and the Admin UI
# backend, which runs on the host, not in the OpenBao container) reaches
# Keycloak at, and the token's "iss" claim reflects the latter, not the
# former. Hit this for real, 2026-10-27: inside Docker Compose, OpenBao
# reaches Keycloak at http://keycloak:8080 (the container-network name),
# but the browser/backend reach it at http://localhost:8081 (the
# host-published port) - so a real login's token carried
# iss=http://localhost:8081/..., which OpenBao rejected outright
# ("invalid issuer (iss) claim") because bound_issuer had been set to
# the container-internal URL instead. KEYCLOAK_ISSUER_HOST (defaults to
# KEYCLOAK_OIDC_HOST, for the common case where they're the same - e.g.
# a real VM where both OpenBao and humans reach Keycloak at one public
# hostname) lets the two be set independently when they're not.
KEYCLOAK_ISSUER_HOST="${KEYCLOAK_ISSUER_HOST:-${KEYCLOAK_OIDC_HOST:-}}"
if [ -z "${KEYCLOAK_OIDC_HOST:-}" ]; then
  echo "    Skipping auth/jwt config - set KEYCLOAK_OIDC_HOST (and KEYCLOAK_REALM_NAME) so OpenBao can reach OIDC discovery."
else
  jq --arg discovery_host "$KEYCLOAK_OIDC_HOST" --arg issuer_host "$KEYCLOAK_ISSUER_HOST" \
     --arg realm "$KEYCLOAK_REALM_NAME" --arg scheme "$KEYCLOAK_OIDC_SCHEME" \
    '.oidc_discovery_url = "\($scheme)://\($discovery_host)/realms/\($realm)" | .bound_issuer = "\($scheme)://\($issuer_host)/realms/\($realm)"' \
    "$ROOT/openbao/auth/human/jwt-config.json" > /tmp/jwt-config.json
  bao write auth/jwt/config @/tmp/jwt-config.json
  echo "    auth/jwt discovery via ${KEYCLOAK_OIDC_SCHEME}://${KEYCLOAK_OIDC_HOST}/realms/${KEYCLOAK_REALM_NAME}, bound_issuer ${KEYCLOAK_OIDC_SCHEME}://${KEYCLOAK_ISSUER_HOST}/realms/${KEYCLOAK_REALM_NAME} (topology=${KEYCLOAK_REALM_TOPOLOGY})."
fi
# The claim name OpenBao binds against is always the flat "vault_roles"
# claim regardless of topology - OpenBao's bound_claims matches a literal
# top-level key, NOT a dot-path into a nested object. Earlier versions of
# this script bound "resource_access.<client>.roles" / "realm_access.roles"
# directly, which looked right but is not real OpenBao syntax - confirmed
# broken against a real server on 2026-10-25 ("claim is missing"). Which
# KIND of Keycloak role (client vs realm) populates "vault_roles" is a
# protocol-mapper choice made in scripts/bootstrap_keycloak.sh
# (KEYCLOAK_ROLE_SOURCE there), not something this script needs to know.
for pair in "prompt-author:prompt-author" "security-officer:security-officer" "auditor:auditor" \
            "domain-reviewer:domain-reviewer" "technical-reviewer:technical-reviewer" \
            "release-manager:release-manager" "space-owner:space-owner" "vault-admin:vault-admin"; do
  kc_role="${pair%%:*}"
  policy="${pair##*:}"
  sed -e "s|__KEYCLOAK_CLIENT_ID__|${KEYCLOAK_CLIENT_ID}|g" \
      -e "s|__KEYCLOAK_ROLE__|${kc_role}|g" \
      -e "s|__POLICY_NAME__|${policy}|g" \
    "$ROOT/openbao/auth/human/role-template.json.tmpl" > "/tmp/role-${kc_role}.json"
  bao write "auth/jwt/role/${kc_role}" @"/tmp/role-${kc_role}.json"
done
echo "    JWT roles bound on vault_roles (populated via ${KEYCLOAK_ROLE_SOURCE}-role mapper, client=${KEYCLOAK_CLIENT_ID} - see scripts/bootstrap_keycloak.sh)."
echo "    Requires audience mapper on the Keycloak client adding '${KEYCLOAK_CLIENT_ID}' to the token's aud claim - also set up by bootstrap_keycloak.sh."

echo "==> Agent auth method: ${AGENT_AUTH_METHOD} (cert rotation mode: ${CERT_ROTATION_MODE})"
case "$AGENT_AUTH_METHOD" in
  cert)
    allowed_cns="${AGENT_ALLOWED_COMMON_NAMES:-*.agents.internal}"
    bao auth enable cert || true
    case "$CERT_ROTATION_MODE" in
      openbao-pki)
        agent_mount="${AGENT_PKI_MOUNT:-pki-agent}"
        agent_domain="${allowed_cns#\*.}"
        ensure_pki_ca "$agent_mount" "${AGENT_PKI_ROLE:-agent-cert}" "$agent_domain" \
          "Agent Client CA" "${AGENT_CERT_TTL:-72h}" "${AGENT_CERT_MAX_TTL:-168h}"
        ca_pem="$(bao read -field=certificate "${agent_mount}/cert/ca")"
        bao policy write "${agent_mount}-issue" - <<EOF
path "${agent_mount}/issue/${AGENT_PKI_ROLE:-agent-cert}" { capabilities = ["create","update"] }
EOF
        echo "    PKI mount '${agent_mount}' ready. Rotate leaf certs with"
        echo "    scripts/pki/rotate_leaf_cert.sh ${agent_mount} ${AGENT_PKI_ROLE:-agent-cert} <cn> <out-dir> -"
        echo "    the root CA stays put, only the leaf (what OpenBao trusts individual"
        echo "    agents by) rotates, so re-running that script never needs this bootstrap again."
        ;;
      manual)
        : "${AGENT_CA_CERT_PATH:?AGENT_CA_CERT_PATH must point at the trusted CA PEM when CERT_ROTATION_MODE=manual}"
        ca_pem="$(cat "$AGENT_CA_CERT_PATH")"
        echo "    Using an externally-issued CA (scripts/pki/generate_ca.sh) - no automated rotation."
        ;;
      *)
        echo "    Unknown CERT_ROTATION_MODE '$CERT_ROTATION_MODE' - cannot configure auth/cert without a CA." >&2
        exit 1
        ;;
    esac
    jq -n --arg ca "$ca_pem" --arg cns "$allowed_cns" \
      '{display_name:"agent-cert-auth", token_policies:["agent-prompt-read"], certificate:$ca, allowed_common_names:$cns, token_ttl:"900", token_max_ttl:"3600"}' \
      > /tmp/agent-cert-role.json
    bao write auth/cert/certs/agent-cert-auth @/tmp/agent-cert-role.json
    echo "    auth/cert enabled. Register each agent's identity with scripts/register_agent_identity.sh."
    ;;
  spiffe)
    echo "    Skipping - SPIFFE/SPIRE agent auth is a stub, not implemented. See openbao/auth/agent/spiffe/README.md." >&2
    ;;
  *)
    echo "    Unknown AGENT_AUTH_METHOD '$AGENT_AUTH_METHOD' - skipping." >&2
    ;;
esac

echo "==> GitOps pipeline writer (AppRole - the sole path that writes new prompt versions)"
bao auth enable approle || true
bao policy write gitops-pipeline-write "$ROOT/openbao/policies/gitops-pipeline-write.hcl"
bao write auth/approle/role/gitops-pipeline \
  token_policies="gitops-pipeline-write" \
  token_ttl=10m \
  token_max_ttl=30m \
  secret_id_ttl=10m \
  secret_id_num_uses=1
echo "    Role 'gitops-pipeline' created. Fetch role_id (auth/approle/role/gitops-pipeline/role-id)"
echo "    and mint a short-lived secret_id per CI run via scripts/mint_gitops_secret_id.py -"
echo "    never store a long-lived secret_id in CI config."

echo "==> GitHub OIDC secret_id minter (auth/jwt-github, separate from Keycloak's auth/jwt)"
if [ -z "${GITHUB_OIDC_BOUND_REPOSITORY:-}" ]; then
  echo "    Skipping - set GITHUB_OIDC_BOUND_REPOSITORY=owner/repo to enable the CI secret_id broker."
  echo "    See openbao/auth/gitops/README.md."
else
  audience="${GITHUB_OIDC_BOUND_AUDIENCE:-openbao}"
  bao policy write gitops-secret-id-mint "$ROOT/openbao/policies/gitops-secret-id-mint.hcl"
  bao auth enable -path=jwt-github jwt || true
  bao write auth/jwt-github/config @"$ROOT/openbao/auth/gitops/jwt-config.json"
  sed -e "s|__GITHUB_REPOSITORY__|${GITHUB_OIDC_BOUND_REPOSITORY}|g" \
      -e "s|__BOUND_AUDIENCE__|${audience}|g" \
      "$ROOT/openbao/auth/gitops/role-template.json.tmpl" \
      > /tmp/gitops-minter-role.json
  bao write auth/jwt-github/role/gitops-secret-id-minter @/tmp/gitops-minter-role.json
  echo "    auth/jwt-github role gitops-secret-id-minter bound to ${GITHUB_OIDC_BOUND_REPOSITORY} (aud=${audience})."
fi

echo "==> Audit device"
echo "    Nothing to do here - as of OpenBao 2.4+, sys/audit/file (the API)"
echo "    rejects audit-device creation outright ('cannot enable audit device"
echo "    via API; use declarative, config-based audit device management"
echo "    instead' - hit for real against this exact image, 2026-10-27)."
echo "    The audit stanza lives in config.hcl(.tmpl) itself, both at"
echo "    openbao/config.hcl.tmpl (VM path) and docker/openbao/config.hcl.tmpl"
echo "    (Docker Compose path) - it's provisioned at server start, not here."

echo "==> Kill switch: mode=${KILL_SWITCH_MODE}"
case "$KILL_SWITCH_MODE" in
  undecided)
    echo "    Skipping - no kill-switch auth path wired up yet. See openbao/policies/kill_switch/README.md."
    ;;
  break_glass_cert)
    bao policy write oncall-kill-switch "$ROOT/openbao/policies/kill_switch/break_glass_cert.hcl"
    oncall_cns="${ONCALL_ALLOWED_COMMON_NAMES:-*.oncall.internal}"
    bao auth enable cert || true
    case "$CERT_ROTATION_MODE" in
      openbao-pki)
        oncall_mount="${ONCALL_PKI_MOUNT:-pki-oncall}"
        oncall_domain="${oncall_cns#\*.}"
        # Longer-lived than agent leaf certs (30d vs 72h) - this is a
        # break-glass credential handed to a person, not a workload that
        # restarts and re-issues itself; still far shorter than the old
        # manual CA's 825-day leaf default.
        ensure_pki_ca "$oncall_mount" "${ONCALL_PKI_ROLE:-oncall-cert}" "$oncall_domain" \
          "On-call CA" "${ONCALL_CERT_TTL:-720h}" "${ONCALL_CERT_MAX_TTL:-1440h}"
        oncall_ca_pem="$(bao read -field=certificate "${oncall_mount}/cert/ca")"
        bao policy write "${oncall_mount}-issue" - <<EOF
path "${oncall_mount}/issue/${ONCALL_PKI_ROLE:-oncall-cert}" { capabilities = ["create","update"] }
EOF
        echo "    PKI mount '${oncall_mount}' ready. Rotate each engineer's break-glass cert with"
        echo "    scripts/pki/rotate_leaf_cert.sh ${oncall_mount} ${ONCALL_PKI_ROLE:-oncall-cert} <cn> <out-dir>."
        ;;
      manual)
        : "${ONCALL_CA_CERT_PATH:?ONCALL_CA_CERT_PATH must point at the on-call CA PEM when CERT_ROTATION_MODE=manual}"
        oncall_ca_pem="$(cat "$ONCALL_CA_CERT_PATH")"
        echo "    Using an externally-issued CA (scripts/pki/generate_ca.sh) - no automated rotation."
        ;;
      *)
        echo "    Unknown CERT_ROTATION_MODE '$CERT_ROTATION_MODE' - cannot configure the break-glass CA." >&2
        exit 1
        ;;
    esac
    # Deliberately a SEPARATE cert role from agent-cert-auth, on a
    # different CA/trust domain (on-call humans, not agent workloads) -
    # token is short-lived (5min/15min) since this is an emergency path,
    # not a long-running service identity.
    jq -n --arg ca "$oncall_ca_pem" --arg cns "$oncall_cns" \
      '{display_name:"oncall-kill-switch", token_policies:["oncall-kill-switch"], certificate:$ca, allowed_common_names:$cns, token_ttl:"300", token_max_ttl:"900"}' \
      > /tmp/oncall-kill-switch-role.json
    bao write auth/cert/certs/oncall-kill-switch @/tmp/oncall-kill-switch-role.json
    echo "    Wired break-glass cert role 'oncall-kill-switch' (separate CA from agent certs by design)."
    echo "    Register each on-call engineer with scripts/register_oncall_identity.sh (audit attribution)."
    echo "    Invoke it with scripts/oncall_kill_switch.sh - bypasses Keycloak and the Admin UI entirely by design."
    ;;
  keycloak_gated)
    bao policy write oncall-kill-switch "$ROOT/openbao/policies/kill_switch/keycloak_gated.hcl"
    echo "    Wired policy. Still need: attach 'oncall-kill-switch' to the relevant auth/jwt role's token_policies by hand."
    ;;
  *)
    echo "    Unknown KILL_SWITCH_AUTH_MODE '$KILL_SWITCH_MODE' - skipping." >&2
    ;;
esac

echo "==> Done."
