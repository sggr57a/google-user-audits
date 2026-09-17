#!/usr/bin/env bash
# Find currently-suspended users whose last login is 5+ years ago (proxy for
# "suspended 5+ years", since Google exposes no 'date suspended' field).
set -euo pipefail

CONFIG="${1:-config.env}"
# shellcheck disable=SC1090
source "$CONFIG"
mkdir -p "$OUT_DIR"

command -v gam >/dev/null 2>&1 || { echo "ERROR: 'gam' (GAMADV-XTD3) not found on PATH." >&2; exit 1; }

echo "==> Exporting all suspended users..."
gam redirect csv "$OUT_DIR/suspended_all.csv" print users \
  query "isSuspended=true" \
  fields primaryEmail,name.fullName,lastLoginTime,creationTime,suspensionReason,orgUnitPath

echo "==> Filtering to lastLoginTime <= $SUSPENDED_BEFORE (never-logged-in accounts kept)..."
python3 - "$OUT_DIR/suspended_all.csv" "$OUT_DIR/suspended_old.csv" "$SUSPENDED_BEFORE" <<'PY'
import csv, sys
src, dst, cutoff = sys.argv[1], sys.argv[2], sys.argv[3]
kept = 0
with open(src, newline='') as f, open(dst, 'w', newline='') as g:
    r = csv.DictReader(f)
    w = csv.DictWriter(g, fieldnames=r.fieldnames)
    w.writeheader()
    for row in r:
        last = (row.get('lastLoginTime') or '')[:10]
        # Blank or 1970-epoch means "never logged in" -> treat as very old.
        if (not last) or last.startswith('1970') or last <= cutoff:
            w.writerow(row); kept += 1
print(f"Matched {kept} long-suspended accounts.")
PY

echo "==> Wrote $OUT_DIR/suspended_old.csv"
