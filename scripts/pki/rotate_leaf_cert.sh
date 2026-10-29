#!/usr/bin/env bash
set -euo pipefail

# Issues a fresh leaf cert from an OpenBao PKI engine mount (the
# "openbao-pki" CERT_ROTATION_MODE wired up in ../bootstrap_openbao.sh)
# and writes it to disk. This is the rotation step itself - run it on a
# schedule (see ./prompt-vault-cert-rotation.service/.timer) well inside
# the role's ttl, and the identity holding the old cert keeps working
# right up until its own expiry; nothing has to be unsealed, re-trusted,
# or re-bootstrapped, because the root CA this leaf chains to never moves.
#
# Usage:
#   rotate_leaf_cert.sh <mount> <role> <common-name> <output-dir> [ttl]
#
# <mount>       e.g. "pki-agent" or "pki-oncall"
# <role>        e.g. "agent-cert" or "oncall-cert" (../bootstrap_openbao.sh)
# <common-name> the exact CN registered for this identity - e.g.
#               "nursing-assistant-agent.agents.internal"
# <output-dir>  where <common-name>.{crt,key} land (ca.pem alongside, for
#               whatever needs to verify the server side of the connection)
# [ttl]         defaults to the role's own ttl if omitted
#
# Requires: bao CLI (authenticated - BAO_TOKEN / BAO_ADDR as usual), jq.
# A token only needs the narrow "<mount>-issue" policy
# ../bootstrap_openbao.sh writes - not root - to run this.

MOUNT="${1:?usage: rotate_leaf_cert.sh <mount> <role> <common-name> <output-dir> [ttl]}"
ROLE="${2:?missing role}"
CN="${3:?missing common-name}"
OUT_DIR="${4:?missing output-dir}"
TTL="${5:-}"

mkdir -p "$OUT_DIR"
SAFE_NAME="$(printf '%s' "$CN" | tr -c 'A-Za-z0-9._-' '_')"

args=(write -format=json "${MOUNT}/issue/${ROLE}" "common_name=${CN}")
if [ -n "$TTL" ]; then
  args+=("ttl=${TTL}")
fi

ISSUE_OUT="$(bao "${args[@]}")"

printf '%s' "$(echo "$ISSUE_OUT" | jq -r '.data.certificate')" > "$OUT_DIR/${SAFE_NAME}.crt"
printf '%s' "$(echo "$ISSUE_OUT" | jq -r '.data.private_key')" > "$OUT_DIR/${SAFE_NAME}.key"
printf '%s' "$(echo "$ISSUE_OUT" | jq -r '.data.issuing_ca')" > "$OUT_DIR/ca.pem"
chmod 600 "$OUT_DIR/${SAFE_NAME}.key"

serial="$(echo "$ISSUE_OUT" | jq -r '.data.serial_number')"
expiration="$(echo "$ISSUE_OUT" | jq -r '.data.expiration')"
echo "Issued ${OUT_DIR}/${SAFE_NAME}.crt (CN=${CN}, serial=${serial}, expires=$(date -d "@${expiration}" -u +%FT%TZ 2>/dev/null || echo "epoch:${expiration}"))"
echo "Whatever uses this cert needs restarting/reloading to pick it up - this script only issues, it doesn't deploy."
