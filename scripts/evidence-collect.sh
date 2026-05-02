#!/usr/bin/env bash
# =============================================================================
# evidence-collect.sh — Deterministic evidence collection
# =============================================================================
# Runs weekly via systemd timer. Collects system snapshots, Lynis audit,
# and Trivy scans from all infrastructure hosts.
#
# Output: /opt/auditor/evidence/<tool>/YYYY-MM-DD/<host>.{json,txt}
set -euo pipefail

EVIDENCE_DIR="/opt/auditor/evidence"
LOG_PREFIX="[$(date +%Y-%m-%dT%H:%M:%S)]"
TODAY=$(date +%Y-%m-%d)

# Infrastructure targets (SSH port 2222)
TARGETS="databases:192.168.1.58 services:192.168.1.59"
DOCKER_HOSTS="databases:192.168.1.58 services:192.168.1.59"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -p 2222"

echo "$LOG_PREFIX Starting evidence collection..."

# =============================================================================
# System Snapshots
# =============================================================================
SNAP_DIR="${EVIDENCE_DIR}/snapshots/${TODAY}"
mkdir -p "$SNAP_DIR"

for target in $TARGETS; do
    name="${target%%:*}"
    host="${target##*:}"
    echo "$LOG_PREFIX Collecting snapshot from $name ($host)..."

    ssh $SSH_OPTS "root@${host}" bash -s <<'SNAPSHOT_EOF' > "${SNAP_DIR}/${name}.json" 2>/dev/null || {
        echo "$LOG_PREFIX WARNING: Failed to collect snapshot from $name"
        continue
    }
{
    echo "{"
    echo "  \"hostname\": \"$(hostname)\","
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"uptime_seconds\": $(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1),"
    echo "  \"load_avg\": \"$(cat /proc/loadavg | cut -d' ' -f1-3)\","
    echo "  \"memory\": {"
    echo "    \"total_mb\": $(free -m | awk '/Mem:/{print $2}'),"
    echo "    \"used_mb\": $(free -m | awk '/Mem:/{print $3}'),"
    echo "    \"available_mb\": $(free -m | awk '/Mem:/{print $7}')"
    echo "  },"
    echo "  \"disk_usage\": ["
    df -h --output=target,size,used,avail,pcent -x tmpfs -x devtmpfs 2>/dev/null | tail -n+2 | while read mount size used avail pct; do
        echo "    {\"mount\": \"$mount\", \"size\": \"$size\", \"used\": \"$used\", \"avail\": \"$avail\", \"pct\": \"$pct\"},"
    done
    echo "    null"
    echo "  ],"

    # Docker info if available
    if command -v docker &>/dev/null; then
        echo "  \"docker_containers\": ["
        docker ps -a --format '{"name":"{{.Names}}","status":"{{.Status}}","image":"{{.Image}}"},' 2>/dev/null || echo '    null'
        echo "    null"
        echo "  ],"
        echo "  \"docker_stats\": ["
        docker stats --no-stream --format '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}","mem_pct":"{{.MemPerc}}"},' 2>/dev/null || echo '    null'
        echo "    null"
        echo "  ]"
    else
        echo "  \"docker_containers\": null,"
        echo "  \"docker_stats\": null"
    fi
    echo "}"
}
SNAPSHOT_EOF
done

echo "$LOG_PREFIX Snapshots collected to ${SNAP_DIR}/"

# =============================================================================
# Lynis Audit (local only — runs on this container)
# =============================================================================
LYNIS_DIR="${EVIDENCE_DIR}/lynis/${TODAY}"
mkdir -p "$LYNIS_DIR"

if command -v lynis &>/dev/null; then
    echo "$LOG_PREFIX Running Lynis audit on local host..."
    lynis audit system --no-colors --quiet --report-file "${LYNIS_DIR}/dev-monitoring.txt" 2>/dev/null || {
        echo "$LOG_PREFIX WARNING: Lynis audit had non-zero exit (normal for findings)"
    }
    # Copy structured data if available
    [ -f /var/log/lynis.log ] && cp /var/log/lynis.log "${LYNIS_DIR}/dev-monitoring-full.log" 2>/dev/null || true
    echo "$LOG_PREFIX Lynis audit saved to ${LYNIS_DIR}/"
else
    echo "$LOG_PREFIX WARNING: Lynis not installed, skipping"
fi

# =============================================================================
# Trivy Image Scan (on Docker hosts)
# =============================================================================
TRIVY_DIR="${EVIDENCE_DIR}/trivy/${TODAY}"
mkdir -p "$TRIVY_DIR"

for target in $DOCKER_HOSTS; do
    name="${target%%:*}"
    host="${target##*:}"
    echo "$LOG_PREFIX Running Trivy scan on $name ($host)..."

    # Get list of images, scan each
    images=$(ssh $SSH_OPTS "root@${host}" "docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>'" 2>/dev/null) || {
        echo "$LOG_PREFIX WARNING: Failed to get images from $name"
        continue
    }

    for image in $images; do
        safe_name=$(echo "$image" | tr '/:' '__')
        trivy image --severity HIGH,CRITICAL --format json "$image" > "${TRIVY_DIR}/${name}_${safe_name}.json" 2>/dev/null || {
            echo "$LOG_PREFIX WARNING: Trivy scan failed for $image on $name"
        }
    done
done

echo "$LOG_PREFIX Trivy scans saved to ${TRIVY_DIR}/"

# =============================================================================
# Summary
# =============================================================================
echo "$LOG_PREFIX Evidence collection complete."
echo "$LOG_PREFIX  - Snapshots: ${SNAP_DIR}/"
echo "$LOG_PREFIX  - Lynis: ${LYNIS_DIR}/"
echo "$LOG_PREFIX  - Trivy: ${TRIVY_DIR}/"
