# Threat Model Calibration — `solo_homelab`

This homelab is operated by a single owner (Wojtek). All severity ratings MUST be calibrated for this context BEFORE writing findings. Default enterprise threat models inflate severity for risks that don't apply here.

**Rule of thumb**: ask "would this finding hold up if the only adversary is (a) external attacker behind Cloudflare, (b) a compromised GitHub Actions workflow on LXC 110?" If neither, the finding is calibrated DOWN.

---

## Trust Zones

| Zone | Members | Trust | Notes |
|---|---|---|---|
| **Owner** | LAN clients of Wojtek (laptops, phones, NAS, IoT VLAN) | Full trust | No co-workers, no contractors, no shared LAN tenants |
| **Semi-trusted compute** | LXC 110 `gh-runner` | Medium trust | Runs external GitHub Actions workflow code (untrusted code source) — isolation matters |
| **External** | Internet via Cloudflare tunnel | Untrusted | Only Cloudflare-fronted services exposed; raw IP is not |
| **Local infra** | All other LXCs/VMs/PVE hosts | Full trust | Single-user infrastructure |

---

## Severity Calibration Matrix

For each common finding class, this is the calibrated severity for `solo_homelab` context. **Apply these adjustments BEFORE writing finding files.**

### Always S1 / S2 — DO NOT downgrade

| Class | Severity | Why retained |
|---|---|---|
| Hardcoded passwords in code/compose with mode 644 | **S2** | Constitution V violation, real credential leak risk |
| SSH key from unknown source in authorized_keys | **S1** | Direct unauthorized access vector |
| Public CF tunnel exposes internal admin UI without auth (e.g. pgAdmin master pw disabled) | **S1** | Internet-facing breach path |
| Vault unseal key plaintext on disk | **S2** | Single point of compromise for entire secret store |
| LXC 110 (gh-runner) privesc paths: `docker` group membership, `CAP_SYS_ADMIN`, no VLAN isolation | **S1/S2** | Semi-trusted endpoint that runs external code |
| Compromised credentials, leaked tokens in logs | **S1** | Real exposure |
| Backup completely missing (no snapshots for >30 days) | **S2** | Recovery impossible |
| Public service vulnerable to known CVE with PoC | **S1** | Internet-exposed |

### Downgraded — apply these

| Class | Default | `solo_homelab` | Rationale |
|---|---|---|---|
| `0.0.0.0` port binding on internal service (Dozzle, Tugtainer, Beszel UI, etc.) | S2 | **S3** | LAN is owner-trusted. Real risk is via gh-runner only — flag specifically the gh-runner path, not generic LAN exposure |
| Service binds to LAN IP `192.168.1.X` (not 0.0.0.0) | S3 | **INFO** | LAN-only, owner-trusted; Traefik routing pattern |
| `:latest` Docker image tag | S2 | **S3** | No SLA, MVP velocity > deterministic deploys; Tugtainer auto-update is a deliberate choice |
| Container missing healthcheck WITH 0 restarts in last 30 days | S2 | **S3** | No observed instability; healthchecks valuable for cloudflared/vault-unseal only |
| Container missing healthcheck WITH >0 restarts | S2 | **S2** | Real instability — keep severity |
| AdGuard DNSSEC off | S3 | **INFO** | Private LAN resolver, no external query path needs DNSSEC |
| pprof / debug endpoints on private LAN service | S3 | **INFO** | Owner-trusted LAN |
| PVE sysctl kernel hardening (kptr_restrict, rp_filter, send_redirects) | S3 | **INFO** | Single-tenant hypervisor, no co-located workloads |
| PVE cluster firewall disabled | S2 | **S3** | LAN trust model; specific gh-runner egress is the real concern, not blanket FW |
| HA + Replication not configured on cluster | S3 | **INFO** | Solo accepts SPOF; HA = 3x RAM/CPU cost for low-prob mitigation |
| Single NIC (no LACP/bond) on PVE host | S3 | **INFO** | Solo accepts SPOF |
| Excluded VM/LXC from backup (deliberate, documented) | S2 | **INFO** | Conscious decision (e.g. VM 300 Windows backup-stopped) |
| Docker socket mount in trusted-only management container (Tugtainer, Dozzle, Beszel) | S2 | **S3** | These ARE management tools; socket access is feature, not bug. Real risk: 8 mounts × LAN exposure → fix LAN exposure (already calibrated) instead of removing socket |
| AppArmor `complain` mode (vs enforce) on unprivileged LXC | S3 | **INFO** | Unprivileged LXC = primary mitigation; AppArmor enforce = defense-in-depth, low marginal value |
| `homarr_default` / `n8n_default` / etc. local Docker network not segmented | S3 | **INFO** | Single-host, single-user |
| Resource limits (`mem_limit`, `cpus`) missing | S3 | **S4** | Risk is OOM kill of one service, not security |
| 9 containers/VMs outside Terraform (pve1, pve2 manually managed) | S3 | **INFO** | Conscious IaC scope decision; document-don't-rewrite stance acceptable |
| Ghost Terraform directory for decommissioned LXC | S3 | **S4** | Real risk: accidental `terraform apply` recreates resource — but easy fix |

### Context overrides — escalate when these apply

If a finding triggers ANY of these, restore **default enterprise severity** and explicitly mark it in the finding:

1. **Public via CF tunnel without auth** — admin UI reachable from internet → S1 regardless of internal calibration
2. **Handles secrets / credentials** (Vault, pgAdmin saved connections, gh-runner tokens) → keep S1/S2
3. **Semi-trusted endpoint can reach it** — if LXC 110 (gh-runner) can reach the misconfigured service → keep S2 even if internal
4. **Active exploitation observed** in logs/journal → S1 escalation regardless of class
5. **Constitution violation** (hardcoded secrets, fallbacks, legacy code) → severity per Constitution, not threat model

---

## How to apply

When writing a finding, ALWAYS include this block at the top:

```markdown
## Threat Model Calibration
- Default enterprise severity: <S1/S2/S3>
- Calibrated severity (`solo_homelab`): <S1/S2/S3/S4/INFO>
- Rationale: <why downgrade applies, OR which override escalates it back>
```

If calibrated severity is INFO, the finding goes to a **separate file** (`/opt/auditor/findings/info/YYYY-MM-DD_<area>.md`) and does **NOT** create Notion entries or ntfy alerts. INFO findings are batched in monthly review summary.

If calibrated severity is S4, finding lives in backlog only (no Notion, no ntfy), but stays in finding file for record.

---

## What "real" findings look like in `solo_homelab` context

Based on actual high-value findings from this homelab:

1. **Constitution I.1 violation discovered** — Ansible playbook silent fallback masked CI Vault disconnect for weeks (M2 25b83d62). The audit value here was finding that *the system violates its own rules*, not generic security best practice.
2. **Notification layer broken for 47 days** (M2 22df8ec6) — 69 Kuma monitors producing zero alerts. Meta-insight: audit produces, human doesn't act → blind-spot loop.
3. **Unknown SSH key from decommissioned VPS** (M2 d2ab915d) — concrete unauthorized access vector, not theoretical risk.

These three are the gold standard. They show:
- **Specificity** (named root cause, not "best practice gap")
- **Actionability** (exact remediation, not "consider hardening")
- **Self-reflection** (system violates its own design intent — most valuable to owner)

When in doubt, ask: "Does this finding teach Wojtek something new about HIS system, or does it just rephrase generic enterprise hygiene?" If the latter, downgrade or skip.

---

## Operational checklist before writing finding

Before writing finding to `/opt/auditor/findings/`:

- [ ] Apply severity calibration matrix above
- [ ] Check context overrides (escalation conditions)
- [ ] Confirm the finding teaches something specific to this homelab
- [ ] If severity calibrated to INFO/S4, route to appropriate destination (info/, backlog only)
- [ ] Include "Threat Model Calibration" block in finding body
