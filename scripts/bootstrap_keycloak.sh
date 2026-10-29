#!/usr/bin/env bash
set -euo pipefail

# Applies ../keycloak/realm-export.json via kcadm.sh. Idempotent: creates
# the realm if absent. The Admin UI client is not in the export (undecided);
# if a client is added there later, this script upserts it and its roles.
#
# Env vars (mirrors terraform/variables.tf — see ../keycloak/README.md):
#   KEYCLOAK_REALM_TOPOLOGY  shared (default) | dedicated
#   KEYCLOAK_REALM_NAME      default: tch (from the export)
#   KEYCLOAK_CLIENT_ID       default: prompt-vault-admin-ui
#   KEYCLOAK_ROLE_SOURCE     client (default) | realm (also create realm roles)
#   OAUTH_IDP_ALIAS          alias for an external OAuth/OIDC identity provider to broker
#                            login through, once a real app is approved (unset: skip - see
#                            that section below)
#   OAUTH_IDP_DISCOVERY_URL  the provider's own /.well-known/openid-configuration URL
#   OAUTH_IDP_CLIENT_ID      from the approved OAuth app
#   OAUTH_IDP_CLIENT_SECRET  from the approved OAuth app
#
# NOT handled here: ../keycloak/realm-export.json's registrationAllowed +
# defaultGroups (self-registration auto-granting vault-viewer) - that's a
# LOCAL-DEV-ONLY convenience applied by Keycloak's own --import-realm in
# the Docker Compose path (../docker/), deliberately not replicated into
# this script's "shared" topology. Turning on self-registration for an
# entire shared org realm is a real consequence for every other team on
# it, not a call one workstream's bootstrap script gets to make silently.
#
# shared: this only touches this workstream's client and its roles. It does
# not assume ownership of the realm, and will not rewrite realm-level
# settings if the realm already exists. Re-running after another team adds
# their own client is safe.
#
# dedicated: this workstream owns the realm. The realm is still created
# thin (enabled/sslRequired only) plus this client — not a full realm
# import — so re-runs remain additive. Set KEYCLOAK_REALM_NAME to a
# workstream-specific value (suggested: prompt-vault).
#
# Requires: kcadm.sh on PATH, authenticated (kcadm.sh config credentials ...)
# against the target Keycloak server before running this.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REALM_FILE="$ROOT/keycloak/realm-export.json"
KEYCLOAK_REALM_TOPOLOGY="${KEYCLOAK_REALM_TOPOLOGY:-shared}"
KEYCLOAK_REALM_NAME="${KEYCLOAK_REALM_NAME:-$(jq -r '.realm' "$REALM_FILE")}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-prompt-vault-admin-ui}"
KEYCLOAK_ROLE_SOURCE="${KEYCLOAK_ROLE_SOURCE:-client}"
EXPORT_CLIENT_ID="$(jq -r '.clients[0].clientId // empty' "$REALM_FILE")"

if [ "$KEYCLOAK_REALM_TOPOLOGY" = "shared" ] && [ "$KEYCLOAK_ROLE_SOURCE" = "realm" ]; then
  echo "WARNING: shared topology with KEYCLOAK_ROLE_SOURCE=realm collides with other backends. Use client roles (the default), or switch topology to dedicated." >&2
fi
if [ "$KEYCLOAK_REALM_TOPOLOGY" = "dedicated" ] && [ "$KEYCLOAK_REALM_NAME" = "tch" ]; then
  echo "WARNING: dedicated topology still using the shared default realm name. Set KEYCLOAK_REALM_NAME to a workstream-specific realm (suggested: prompt-vault)." >&2
fi

echo "==> Topology: ${KEYCLOAK_REALM_TOPOLOGY}  realm: ${KEYCLOAK_REALM_NAME}  client: ${EXPORT_CLIENT_ID:-none (Admin UI deferred)}"

client_payload=""
client_roles=""
if [ -n "$EXPORT_CLIENT_ID" ]; then
  client_payload="$(jq --arg cid "$KEYCLOAK_CLIENT_ID" --arg src "$EXPORT_CLIENT_ID" '
    .clients[] | select(.clientId == $src) | .clientId = $cid
  ' "$REALM_FILE")"
  client_roles="$(jq -r --arg src "$EXPORT_CLIENT_ID" '.roles.client[$src][]?.name // empty' "$REALM_FILE")"
fi

if kcadm.sh get "realms/${KEYCLOAK_REALM_NAME}" >/dev/null 2>&1; then
  if [ "$KEYCLOAK_REALM_TOPOLOGY" = "shared" ]; then
    echo "    Realm already exists - leaving realm-level settings as-is (shared across backends)."
  else
    echo "    Realm already exists - dedicated topology owns it, but re-runs still only upsert this client."
  fi
else
  echo "    Realm does not exist - creating with enabled/sslRequired only (no other backends' config)."
  jq -n --arg realm "$KEYCLOAK_REALM_NAME" \
    '{realm: $realm, enabled: true, sslRequired: "external"}' \
    | kcadm.sh create realms -f -
fi

existing_client_uuid=""
if [ -z "$EXPORT_CLIENT_ID" ]; then
  echo "==> No client in realm-export.json — skipping Admin UI client (not decided yet)."
else
echo "==> Client: ${KEYCLOAK_CLIENT_ID}"
existing_client_uuid="$(kcadm.sh get clients -r "$KEYCLOAK_REALM_NAME" -q "clientId=${KEYCLOAK_CLIENT_ID}" --fields id --format csv --noquotes | tail -n +1 | head -n1 || true)"

if [ -n "${existing_client_uuid:-}" ]; then
  echo "    Updating existing client ${existing_client_uuid}"
  echo "$client_payload" | kcadm.sh update "clients/${existing_client_uuid}" -r "$KEYCLOAK_REALM_NAME" -f -
else
  echo "    Creating client"
  echo "$client_payload" | kcadm.sh create clients -r "$KEYCLOAK_REALM_NAME" -f -
  existing_client_uuid="$(kcadm.sh get clients -r "$KEYCLOAK_REALM_NAME" -q "clientId=${KEYCLOAK_CLIENT_ID}" --fields id --format csv --noquotes | tail -n +1 | head -n1)"
fi
fi

if [ -n "$EXPORT_CLIENT_ID" ]; then
echo "==> Client roles"
echo "$client_roles" | while read -r role; do
  [ -z "$role" ] && continue
  if kcadm.sh get "clients/${existing_client_uuid}/roles/${role}" -r "$KEYCLOAK_REALM_NAME" >/dev/null 2>&1; then
    echo "    ${role} already exists"
  else
    kcadm.sh create "clients/${existing_client_uuid}/roles" -r "$KEYCLOAK_REALM_NAME" -s "name=${role}"
    echo "    created ${role}"
  fi
done

if [ "$KEYCLOAK_ROLE_SOURCE" = "realm" ]; then
  echo "==> Realm roles (KEYCLOAK_ROLE_SOURCE=realm)"
  echo "$client_roles" | while read -r role; do
    [ -z "$role" ] && continue
    if kcadm.sh get "roles/${role}" -r "$KEYCLOAK_REALM_NAME" >/dev/null 2>&1; then
      echo "    ${role} already exists"
    else
      kcadm.sh create roles -r "$KEYCLOAK_REALM_NAME" -s "name=${role}"
      echo "    created realm role ${role}"
    fi
  done
fi

echo "==> Protocol mappers (flat vault_roles claim + audience)"
# OpenBao's bound_claims matches a literal top-level claim key - it does
# NOT traverse dot-paths into nested objects. Keycloak's own
# resource_access.<client>.roles / realm_access.roles claims ARE nested,
# so binding against those dotted strings directly looks plausible but
# silently fails ("claim is missing") - confirmed against a real server
# on 2026-10-25. These two mappers flatten what OpenBao actually needs:
# a top-level "vault_roles" array, and this client's own ID in "aud"
# (Keycloak does not include a client in its own token's audience unless
# a mapper says to - also confirmed missing against a real server).
existing_mappers="$(kcadm.sh get "clients/${existing_client_uuid}/protocol-mappers/models" -r "$KEYCLOAK_REALM_NAME")"

if echo "$existing_mappers" | jq -e '.[] | select(.name == "vault-roles-flat")' >/dev/null; then
  echo "    vault-roles-flat mapper already exists"
else
  if [ "$KEYCLOAK_ROLE_SOURCE" = "realm" ]; then
    mapper_type="oidc-usermodel-realm-role-mapper"
    mapper_config='{"claim.name":"vault_roles","jsonType.label":"String","multivalued":"true","id.token.claim":"true","access.token.claim":"true"}'
  else
    mapper_type="oidc-usermodel-client-role-mapper"
    mapper_config="$(jq -n --arg cid "$KEYCLOAK_CLIENT_ID" '{"usermodel.clientRoleMapping.clientId":$cid,"claim.name":"vault_roles","jsonType.label":"String","multivalued":"true","id.token.claim":"true","access.token.claim":"true"}')"
  fi
  jq -n --arg type "$mapper_type" --argjson config "$mapper_config" \
    '{name:"vault-roles-flat", protocol:"openid-connect", protocolMapper:$type, config:$config}' \
    | kcadm.sh create "clients/${existing_client_uuid}/protocol-mappers/models" -r "$KEYCLOAK_REALM_NAME" -f -
  echo "    created vault-roles-flat (${mapper_type})"
fi

if echo "$existing_mappers" | jq -e '.[] | select(.name == "vault-audience")' >/dev/null; then
  echo "    vault-audience mapper already exists"
else
  jq -n --arg cid "$KEYCLOAK_CLIENT_ID" \
    '{name:"vault-audience", protocol:"openid-connect", protocolMapper:"oidc-audience-mapper",
      config:{"included.client.audience":$cid,"id.token.claim":"false","access.token.claim":"true"}}' \
    | kcadm.sh create "clients/${existing_client_uuid}/protocol-mappers/models" -r "$KEYCLOAK_REALM_NAME" -f -
    echo "    created vault-audience"
fi
fi

echo "==> External OAuth/OIDC identity provider (optional - unset to skip)"
if [ -z "${OAUTH_IDP_ALIAS:-}" ]; then
  echo "    Skipping - set OAUTH_IDP_ALIAS (+ OAUTH_IDP_DISCOVERY_URL, OAUTH_IDP_CLIENT_ID,"
  echo "    OAUTH_IDP_CLIENT_SECRET) once a real OAuth app (Google/Okta/Azure AD/...) has been"
  echo "    approved and provisioned. Local testing until then uses Keycloak's own login +"
  echo "    self-registration instead - see the realm's registrationAllowed and defaultGroups"
  echo "    (self-registration lands users in tch-users; no Admin UI client until that is decided)."
else
  : "${OAUTH_IDP_DISCOVERY_URL:?OAUTH_IDP_DISCOVERY_URL is required when OAUTH_IDP_ALIAS is set}"
  : "${OAUTH_IDP_CLIENT_ID:?OAUTH_IDP_CLIENT_ID is required when OAUTH_IDP_ALIAS is set}"
  : "${OAUTH_IDP_CLIENT_SECRET:?OAUTH_IDP_CLIENT_SECRET is required when OAUTH_IDP_ALIAS is set}"
  if kcadm.sh get "identity-provider/instances/${OAUTH_IDP_ALIAS}" -r "$KEYCLOAK_REALM_NAME" >/dev/null 2>&1; then
    echo "    Identity provider '${OAUTH_IDP_ALIAS}' already exists - leaving it as-is (re-run"
    echo "    after deleting it first if the discovery URL or credentials changed)."
  else
    # import-config discovers the provider's real endpoints (authorization,
    # token, userinfo, jwks, issuer) from its own OIDC discovery document,
    # rather than hand-specifying each one - verified against a real
    # provider (Google's public discovery URL) and a real Keycloak server,
    # 2026-10-27. generic "oidc", not a provider-specific providerId, since
    # this needs to work for whichever provider ends up approved.
    kcadm.sh create identity-provider/import-config -r "$KEYCLOAK_REALM_NAME" \
      -s providerId=oidc -s fromUrl="$OAUTH_IDP_DISCOVERY_URL" -o \
      | jq --arg alias "$OAUTH_IDP_ALIAS" --arg cid "$OAUTH_IDP_CLIENT_ID" --arg secret "$OAUTH_IDP_CLIENT_SECRET" \
        '{alias: $alias, providerId: "oidc", enabled: true, config: (. + {clientId: $cid, clientSecret: $secret})}' \
      | kcadm.sh create identity-provider/instances -r "$KEYCLOAK_REALM_NAME" -f -
    echo "    Created identity provider '${OAUTH_IDP_ALIAS}' from ${OAUTH_IDP_DISCOVERY_URL}."
    echo "    It'll appear as a login option on the realm's login page automatically - no"
    echo "    Admin UI backend change needed, since that backend only ever talks to Keycloak's"
    echo "    own token endpoint, never to the upstream provider directly."
  fi
fi

echo "==> Done. Realm ${KEYCLOAK_REALM_NAME} is ready. Admin UI client is not created until it is added to realm-export.json."
