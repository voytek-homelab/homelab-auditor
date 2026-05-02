# CLAUDE.md - Homelab AI Auditor (LXC 504)

AI-powered infrastructure auditor for homelab. Combines deterministic evidence collection with exploratory AI auditing.

## This Host (LXC 505 - dev-projects)

- **IP:** 192.168.1.35
- **SSH:** Port 2222
- **User:** `voytek` (sudo NOPASSWD:ALL)
- **Purpose:** Primary dev container — all projects consolidated here, including auditor

### Running Audits

```bash
# Interactive audit (as voytek)
audit                              # alias for claude --dangerously-skip-permissions

# Full sweep (automated cycle)
audit-sweep                        # reads state, decides what to audit
audit-sweep "Focus on network"     # sweep with specific focus

# Check status
audit-status                       # timer status
audit-backlog                      # pending items
audit-findings                     # recent findings
audit-journal                      # audit history
```

---

## Auditor Data Layout

```
/opt/auditor/
├── evidence/           # Deterministic collection (Lynis, Trivy, snapshots)
│   ├── snapshots/YYYY-MM-DD/   # System snapshots per host
│   ├── lynis/YYYY-MM-DD/       # Lynis audit reports
│   └── trivy/YYYY-MM-DD/       # Trivy vulnerability scans
├── signals/            # Lightweight signals (Uptime Kuma, Docker events)
│   └── YYYY-MM-DD.json
├── journal/            # Audit session logs (what was done, when)
├── coverage/           # Coverage map (what areas checked, when)
│   └── coverage-map.json
├── backlog/            # Items to investigate
│   └── backlog.json
├── findings/           # Audit findings (issues to fix)
├── reports/            # Full sweep reports
└── logs/               # Script logs
```

---

## Infrastructure Map

### Proxmox Nodes

| Node | IP | Role |
|------|-----|------|
| **PVE0** | 192.168.1.7 | Main — LXC 203-205, 500-506 |
| **PVE1** | 192.168.1.6 | Websites (WordPress, Strapi) |
| **PVE2** | 192.168.1.18 | Proxmox Backup Server |

### LXC Containers (PVE0)

| LXC | Name | IP | SSH | Services |
|-----|------|-----|-----|----------|
| 110 | gh-runner | 192.168.1.60 | 2222 | GitHub Actions self-hosted runner |
| 203 | databases | 192.168.1.58 | 2222 | PostgreSQL, Redis, Qdrant + agents |
| 204 | services | 192.168.1.59 | 2222 | Traefik, n8n, Vault, AdGuard, Homarr, ntfy, Beszel Hub, Uptime Kuma, Tugtainer, Dozzle, Cloudflared |
| 205 | claude-monitor | 192.168.1.61 | 2222 | Claude Code Headless + Monitor webapp |
| **505** | **dev-projects** | **192.168.1.35** | **2222** | **This host — all dev + AI auditor** |

### Network Architecture

```
Internet → Cloudflared (204) → Traefik (204) → Services
                                    │
         ┌──────────────────────────┼──────────────────┐
         ▼                          ▼                   ▼
    LXC 203 (DB)           LXC 204 (Services)    LXC 205 (Monitor)
    PostgreSQL              Traefik, n8n           Claude Headless
    Redis, Qdrant           Vault, AdGuard         Monitor webapp
```

### Services URLs

| Service | URL |
|---------|-----|
| Homarr | `https://homarr.voytek-homelab.com` |
| Uptime Kuma | `https://uptime.voytek-homelab.com` (API: `http://192.168.1.59:3001`) |
| Dozzle | `https://dozzle.voytek-homelab.com` |
| Beszel | `https://beszel.voytek-homelab.com` |
| Traefik | `https://traefik.voytek-homelab.com` |
| n8n | `https://n8n.voytek-homelab.com` |
| AdGuard | `https://adguard.voytek-homelab.com` |
| ntfy | `https://ntfy.voytek-homelab.com` |
| Vault | `https://vault.voytek-homelab.com` |
| pgAdmin | `https://pgadmin.voytek-homelab.com` |
| Claude Monitor | `https://claude-monitor.voytek-homelab.com` |

---

## SSH Access

Pre-configured via `~/.ssh/config`:

```bash
ssh databases         # 192.168.1.58 (PostgreSQL, Redis, Qdrant)
ssh services          # 192.168.1.59 (Traefik, n8n, Vault, etc.)
ssh claude-monitor    # 192.168.1.61 (Claude Code Headless)
ssh pve0              # 192.168.1.7 (Proxmox host)
```

All use port 2222, user root, with id_local key.

---

## Audit Protocol

### Coverage Map

The file `/opt/auditor/coverage/coverage-map.json` tracks 28 infrastructure areas grouped by domain:
- **network**: vlan, firewall, dns, switches, inter-vlan, wifi
- **docker**: isolation, resources, compose, healthchecks, images
- **lxc**: security, resources, kernel, template-compliance
- **proxmox**: storage, backup, cluster, updates
- **iac**: terraform-drift, ansible-drift
- **services**: traefik, vault, adguard, monitoring
- **cross-cutting**: spof, secrets, access-control, disaster-recovery

Each area has `last_audited` (ISO date or null) and `finding_count`.

### Backlog

The file `/opt/auditor/backlog/backlog.json` tracks items to investigate. Items have:
- `id`, `area`, `title`, `priority` (1-5, 1=highest), `status` (pending/in_progress/done), `added_date`

### Audit Session Flow

1. Read coverage map → identify gaps (null or oldest `last_audited`)
2. Read signals → prioritize active incidents
3. Read backlog → pick highest priority pending items
4. Execute 2-3 focused audits via SSH
5. Write findings to `/opt/auditor/findings/YYYY-MM-DD_<area>.md`
6. Write journal entry to `/opt/auditor/journal/YYYY-MM-DD_<HH:MM>.md`
7. Update coverage map timestamps
8. Update backlog (mark done, add new items)
9. CRITICAL findings → ntfy alert

### Finding Format

```markdown
# Finding: <title>
- **Area:** <coverage map area>
- **Severity:** S1 (critical) / S2 (high) / S3 (medium) / S4 (low)
- **Host:** <affected host(s)>
- **Evidence:** <exact command output or log line>
- **Impact:** <what breaks if ignored>
- **Fix:** <step-by-step remediation>
- **Validation:** <how to confirm fix>
```

### Journal Entry Format

```markdown
# Audit Journal — YYYY-MM-DD HH:MM
## Areas Audited
- <area 1>: <summary of findings>
- <area 2>: <summary of findings>

## Key Findings
1. <finding summary>

## Coverage Map Updates
- <area>: last_audited updated to today

## Backlog Changes
- Added: <new items>
- Completed: <resolved items>

## Next Session Suggestions
- <what to audit next based on gaps>
```

---

## Agents

Available agents for delegation during audits:

| Agent | Purpose |
|-------|---------|
| `audit-orchestrator` | Coordinates audit sessions, manages state |
| `homelab-reliability-auditor` | Deep reliability analysis, incident playbooks |
| `homelab-network-engineer` | Network diagnostics, VLAN/firewall analysis |
| `homelab-container-ops` | Docker/LXC troubleshooting, optimization |
| `homelab-observability-builder` | Monitoring gaps, alerting, SLO analysis |
| `homelab-research-coordinator` | Technology research, best practices |

---

## Key Commands for Auditing

```bash
# On infrastructure hosts (via SSH):
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"
docker stats --no-stream
docker system df
docker inspect <container> | jq '.[0].State.RestartCount, .[0].HostConfig.Memory'
uptime && free -h && df -h
dmesg -T | tail -50
ss -tulpn | head -30

# ntfy notification (for critical findings):
curl -sf -d "CRITICAL: <message>" \
     -H "Title: Homelab Audit CRITICAL" \
     -H "Priority: urgent" \
     -H "Tags: rotating_light" \
     "https://ntfy.voytek-homelab.com/homelab-alerts"
```

---

## Notion Reporting

Audit sweep results are reported to Notion via the `notion` MCP server (`.mcp.json`).

### Configuration
- **MCP config:** `.mcp.json` (gitignored — contains Notion API token)
- **Findings database ID:** `657a5c98-2d5a-4d26-82bc-e72eb052e43f`
- **Parent page (Homelab Auditor):** `31886bac-70f5-814f-9aac-cb5c8f4910e5`

### CRITICAL: How to Report Findings

Each finding MUST be inserted as a **row in the Findings database**, NOT as a child page under the parent page.

Use `notion-create-pages` with `database_id` (not `parent.page_id`):

```json
{
  "database_id": "657a5c98-2d5a-4d26-82bc-e72eb052e43f",
  "pages": [{
    "properties": {
      "Tytuł": "Finding title",
      "Severity": "S1-krytyczny",
      "Host": "services",
      "Obszar": "Docker",
      "Status": "Nowy",
      "Opis": "Short description of the finding",
      "date:Data:start": "2026-03-07",
      "date:Data:is_datetime": 0
    },
    "content": "## Opis problemu\n...\n## Dowody\n...\n## Naprawa\n...\n## Weryfikacja\n..."
  }]
}
```

**Property values** (must match exactly):
- **Severity:** `S1-krytyczny`, `S2-wysoki`, `S3-średni`, `S4-niski`
- **Host:** `databases`, `services`, `gh-runner`, `pve0`
- **Obszar:** `Docker`, `SSH`, `Firewall`, `TLS/SSL`, `Backup`, `Monitoring`, `Uprawnienia`, `Sieć`, `Zasoby`, `Aktualizacje`, `Logi`, `Secrets`
- **Status:** `Nowy` (always for new findings)

### When to Report
- **YES:** After automated sweeps (`audit-sweep`)
- **NO:** During interactive debugging sessions
