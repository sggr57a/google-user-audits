# GAM Suspended-Account Drive Audit (Vault + Data Transfer)

Identify Drive data owned by accounts suspended 5+ years that is either
**not shared with anyone** or **stale** (not modified within your 1–2 year cutoff),
without unsuspending the accounts.

## What this does / does not do

- **Does:** find long-suspended users, archive their Drive to Google Vault (safety/compliance),
  transfer each user's Drive to an active *holding* account, then inventory the files with
  sharing state + timestamps and flag `not-shared` and `stale` files.
- **Does NOT:** tell you the last time a file was *viewed by anyone*. Google's Drive API has no
  domain-wide "last viewed" field, and the Drive audit log is retained only ~180 days, so a
  1–2 year lookback is impossible retroactively. We use **`modifiedTime`** as the staleness proxy.
- **Attribution caveat:** after a Data Transfer, files are owned by the holding account and
  `viewedByMeTime` reflects the holding account, not the original owner. Original per-user
  attribution is preserved via the before/after file-ID diff in `03`, and Vault (`02`) keeps an
  untouched archive of each user's original data.

## Prerequisites

1. **GAMADV-XTD3** installed and configured (the actively maintained GAM fork):
   https://github.com/taers232c/GAMADV-XTD3 — the `gam` command must be on your PATH.
2. A super-admin project with **domain-wide delegation** and these API scopes authorized:
   - Admin Directory (users, read)
   - Data Transfer (`https://www.googleapis.com/auth/admin.datatransfer`)
   - Drive (`https://www.googleapis.com/auth/drive`)
   - Vault (`https://www.googleapis.com/auth/ediscovery`) — only if you run `02`
3. **Google Vault licenses** assigned appropriately (only needed for the Vault step).
4. An **active holding account** (e.g. `drive-audit-holding@yourdomain.com`) with enough Drive
   storage. Use a *dedicated* holding account with no other activity so the diff attribution in
   `03` is accurate.
5. `python3` and `bash` available locally.

## Setup

```bash
cp config.example.env config.env
# edit config.env with your domain, holding account, and cutoff dates
```

## Run order

```bash
./01-find-old-suspended.sh config.env       # -> output/suspended_old.csv
./02-vault-archive.sh      config.env       # optional: Vault matter + per-user Drive exports
./03-transfer-and-audit.sh config.env       # -> output/audit_<user>.csv (+ combined)
python3 04-filter-stale-unshared.py config.env
# -> output/flagged_not_shared.csv, output/flagged_stale.csv, output/flagged_both.csv
```

## Reviewing results

- `flagged_not_shared.csv` — files where `shared = False` (only the owner ever had access).
- `flagged_stale.csv` — files with `modifiedTime` older than `STALE_BEFORE`.
- `flagged_both.csv` — the intersection (strongest candidates for cleanup).

Always spot-check before deleting anything. Vault exports from `02` are your safety net.
