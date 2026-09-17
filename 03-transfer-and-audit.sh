#!/usr/bin/env bash
# For each long-suspended user: Data Transfer their Drive to the holding account,
# then inventory the newly-owned files (attributed via a before/after file-ID diff).
set -euo pipefail

CONFIG="${1:-config.env}"
# shellcheck disable=SC1090
source "$CONFIG"

command -v gam >/dev/null 2>&1 || { echo "ERROR: 'gam' not found on PATH." >&2; exit 1; }
[ -f "$OUT_DIR/suspended_old.csv" ] || { echo "ERROR: run 01 first." >&2; exit 1; }
mkdir -p "$OUT_DIR"

FIELDS="id,name,mimetype,shared,owners,createdtime,modifiedtime,viewedbymetime,size"
COMBINED="$OUT_DIR/audit_combined.csv"
: > "$COMBINED"
COMBINED_HEADER_WRITTEN=0

snapshot_ids () {  # $1 = output file of current file IDs owned by holding account
  gam redirect csv "$1" user "$HOLDING_ACCOUNT" print filelist \
    fields id showownedby me
}

tail -n +2 "$OUT_DIR/suspended_old.csv" | while IFS=',' read -r email rest; do
  [ -n "$email" ] || continue
  echo "=================================================================="
  echo "==> Processing $email"

  BEFORE="$OUT_DIR/.before_${email}.csv"
  AFTER="$OUT_DIR/.after_${email}.csv"
  USER_AUDIT="$OUT_DIR/audit_${email}.csv"

  echo "    Snapshotting holding-account files (before)..."
  snapshot_ids "$BEFORE"

  echo "    Creating Data Transfer of Drive: $email -> $HOLDING_ACCOUNT"
  gam create datatransfer "$email" gdrive "$HOLDING_ACCOUNT" privacy_level private,shared \
    || { echo "    ERROR: transfer request failed for $email; skipping." >&2; continue; }

  echo "    Waiting for transfer to complete (polling)..."
  # Column/status names can vary slightly by GAM version; this greps the user's row for a
  # completed status. Adjust the pattern if your GAM prints different wording.
  for _ in $(seq 1 120); do
    if gam print datatransfers 2>/dev/null \
         | awk -F',' -v u="$email" 'tolower($0) ~ tolower(u) && tolower($0) ~ /completed/ {found=1} END{exit !found}'; then
      echo "    Transfer completed."
      break
    fi
    sleep 30
  done

  echo "    Snapshotting holding-account files (after)..."
  snapshot_ids "$AFTER"

  echo "    Inventorying transferred files with sharing + timestamps..."
  gam redirect csv "$OUT_DIR/.full_${email}.csv" user "$HOLDING_ACCOUNT" print filelist \
    fields "$FIELDS" showownedby me

  # Keep only files that are NEW since 'before' (i.e., this user's transferred files),
  # and tag them with the source user.
  python3 - "$BEFORE" "$OUT_DIR/.full_${email}.csv" "$USER_AUDIT" "$email" <<'PY'
import csv, sys
before_f, full_f, out_f, source = sys.argv[1:5]
with open(before_f, newline='') as f:
    before = {row['id'] for row in csv.DictReader(f) if row.get('id')}
with open(full_f, newline='') as f, open(out_f, 'w', newline='') as g:
    r = csv.DictReader(f)
    fields = ['source_user'] + r.fieldnames
    w = csv.DictWriter(g, fieldnames=fields); w.writeheader()
    n = 0
    for row in r:
        if row.get('id') and row['id'] not in before:
            row['source_user'] = source; w.writerow(row); n += 1
print(f"    {source}: {n} newly-transferred files recorded.")
PY

  # Append to combined file.
  if [ "$COMBINED_HEADER_WRITTEN" -eq 0 ]; then
    cat "$USER_AUDIT" >> "$COMBINED"; COMBINED_HEADER_WRITTEN=1
  else
    tail -n +2 "$USER_AUDIT" >> "$COMBINED"
  fi

  rm -f "$BEFORE" "$AFTER" "$OUT_DIR/.full_${email}.csv"
done

echo "==> Combined inventory: $COMBINED"
