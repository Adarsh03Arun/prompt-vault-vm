#!/usr/bin/env bash
set -euo pipefail

# Prunes OpenBao's own file audit log of entries older than a retention
# period - OpenBao's file audit device has no built-in retention or
# rotation of its own (confirmed: it just appends forever). Compares ISO
# 8601 "time" fields as plain strings, which sorts chronologically
# correctly without needing a date-parsing library.
#
# Usage: prune_audit_log.sh <audit-log-path> [retention-days]
#
# Default retention: 1826 days (~5 years) - same number as
# PROMPT_RETENTION_PERIOD in ../scripts/bootstrap_openbao.sh, resolved
# 2026-10-27. Whether 5 years is the right number long-term still needs
# compliance input - see ../CONTEXT.md.
#
# Run this on a schedule (cron/systemd timer) - same deferred-scheduling
# situation as ./pki/rotate_leaf_cert.sh, see
# ./pki/prompt-vault-cert-rotation.timer.tmpl for the pattern.
#
# Requires: jq.

LOG_PATH="${1:?usage: prune_audit_log.sh <audit-log-path> [retention-days]}"
RETENTION_DAYS="${2:-1826}"

# Epoch arithmetic, not `date -d "-N days"` - BusyBox's date (the one in
# the openbao/openbao:2.4 Alpine image this actually runs against) has no
# relative-offset support at all, only `@epoch`. Confirmed by actually
# running this against that image (2026-10-27): the GNU-only "-N days"
# form failed silently, and the fallback BSD "-v" form isn't understood
# by BusyBox either - the two combined produced an empty $CUTOFF, which
# made every line compare as "newer" and nothing ever got pruned.
NOW_EPOCH="$(date -u +%s)"
CUTOFF_EPOCH=$((NOW_EPOCH - RETENTION_DAYS * 86400))
CUTOFF="$(date -u -d "@${CUTOFF_EPOCH}" +%Y-%m-%dT%H:%M:%S.000000000Z 2>/dev/null \
  || date -u -r "${CUTOFF_EPOCH}" +%Y-%m-%dT%H:%M:%S.000000000Z)"

TMP="$(mktemp)"
kept=0
dropped=0
while IFS= read -r line; do
  line_time="$(printf '%s' "$line" | jq -r '.time // empty' 2>/dev/null || true)"
  # Keep anything we can't parse the time of, rather than silently
  # dropping a malformed-but-possibly-important line.
  if [ -z "$line_time" ] || [ "$line_time" \> "$CUTOFF" ]; then
    printf '%s\n' "$line" >> "$TMP"
    kept=$((kept + 1))
  else
    dropped=$((dropped + 1))
  fi
done < "$LOG_PATH"

mv "$TMP" "$LOG_PATH"
echo "Pruned $LOG_PATH: kept $kept, dropped $dropped (older than $RETENTION_DAYS days, cutoff $CUTOFF)."
