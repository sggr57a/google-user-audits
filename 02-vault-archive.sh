#!/usr/bin/env bash
# OPTIONAL: create a Google Vault matter and a Drive export per long-suspended user,
# so you keep an untouched, authoritative archive before any Data Transfer.
# Requires Vault licenses + ediscovery scope. Downloads are async; see the note at the end.
set -euo pipefail

CONFIG="${1:-config.env}"
# shellcheck disable=SC1090
source "$CONFIG"

command -v gam >/dev/null 2>&1 || { echo "ERROR: 'gam' not found on PATH." >&2; exit 1; }
[ -f "$OUT_DIR/suspended_old.csv" ] || { echo "ERROR: run 01 first." >&2; exit 1; }

MATTER_NAME="${VAULT_MATTER_PREFIX} $(date +%F)"
echo "==> Creating Vault matter: $MATTER_NAME"
gam create matter name "$MATTER_NAME" \
  description "Drive archive of 5+ year suspended accounts prior to cleanup review"

# Look up the matter id we just created.
MATTER_ID="$(gam print matters | awk -F',' -v n="$MATTER_NAME" 'NR==1{for(i=1;i<=NF;i++){if($i=="matterId")mi=i;if($i=="name")nm=i};next} $nm==n{print $mi; exit}')"
[ -n "${MATTER_ID:-}" ] || { echo "ERROR: could not resolve matterId for '$MATTER_NAME'." >&2; exit 1; }
echo "    matterId = $MATTER_ID"

# Create one Drive export per user.
tail -n +2 "$OUT_DIR/suspended_old.csv" | while IFS=',' read -r email rest; do
  [ -n "$email" ] || continue
  echo "==> Creating Vault Drive export for $email"
  gam create export matter "$MATTER_ID" \
    name "drive_${email}" corpus drive accounts "$email" || \
    echo "    WARNING: export creation failed for $email (check Vault license/scope)."
done

cat <<EOF

Vault exports are prepared asynchronously. When they show as COMPLETED you can download them:

  gam print exports matter $MATTER_ID
  gam download export matter $MATTER_ID <exportName> targetfolder $OUT_DIR/vault

EOF
