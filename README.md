# homelab-auditor — ARCHIVED (2026-05)

> **Status:** archived as of 2026-05-14. This repository is no longer
> maintained and the producer cron has been stopped. Read-only mirror for
> historical reference only.

## Successor

Active development moved to **`voytek-homelab/homelab-watch`** (private).
The successor closes the audit → fix → verify loop that this project never
addressed: detected findings flow into a Postgres-backed UI where the
operator triages, a Claude Code agent generates and executes remediation
after explicit approval, and the next audit auto-verifies the fix.

Because the successor repo is private, public links from this repo's
issues, README, or wiki cannot deep-link there. Operators with access can
request a working tree or PR review by contacting wojciech.drezewski@gmail.com.

## Archive details

- Producer timer (`homelab-auditor-sweep.timer` on LXC 505) stopped and
  disabled on 2026-05-14.
- Working directory `/opt/auditor` archived to
  `/var/backups/old-auditor-archive-2026-05.tar.gz` (sha256: `225471eac2f226d20efa648f4d05a730f8a98b3dd28b7126b463d0395f4c3cf6`).
- Active S1/S2 findings (4 items) migrated to homelab-watch on 2026-05-14;
  remaining ~160 archival items remain in Notion in-place (no migration).
- Last commit on `main`: `f98238e` (2026-05-06).

See Plan 08-02 SUMMARY in the successor repo for the full cutover trail.
