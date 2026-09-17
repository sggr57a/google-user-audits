#!/usr/bin/env python3
"""Split the combined Drive inventory into flagged sets:
- not shared with anyone (shared == False)
- stale (modifiedTime older than STALE_BEFORE)
- both (intersection)
Usage: python3 04-filter-stale-unshared.py [config.env]
"""
import csv, os, sys

def load_env(path):
    env = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env

cfg = load_env(sys.argv[1] if len(sys.argv) > 1 else 'config.env')
out_dir = cfg.get('OUT_DIR', './output')
stale_before = cfg['STALE_BEFORE']  # YYYY-MM-DD
combined = os.path.join(out_dir, 'audit_combined.csv')

if not os.path.exists(combined):
    sys.exit(f"ERROR: {combined} not found; run 03 first.")

def is_not_shared(row):
    return str(row.get('shared', '')).strip().lower() in ('false', '', 'none')

def is_stale(row):
    mt = (row.get('modifiedTime') or row.get('modifiedtime') or '')[:10]
    return bool(mt) and mt <= stale_before

with open(combined, newline='') as f:
    rows = list(csv.DictReader(f))
    fieldnames = list(rows[0].keys()) if rows else []

def dump(name, predicate):
    path = os.path.join(out_dir, name)
    hits = [r for r in rows if predicate(r)]
    with open(path, 'w', newline='') as g:
        w = csv.DictWriter(g, fieldnames=fieldnames); w.writeheader()
        w.writerows(hits)
    print(f"{name}: {len(hits)} files")

dump('flagged_not_shared.csv', is_not_shared)
dump('flagged_stale.csv', is_stale)
dump('flagged_both.csv', lambda r: is_not_shared(r) and is_stale(r))
print(f"Wrote flagged CSVs to {out_dir}/")
