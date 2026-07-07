#!/usr/bin/env bash
#
# test_dashboard.sh - Put load on the system and confirm Netdata sees it
#
# What this does:
#   1. Checks the Netdata API is reachable
#   2. Records a "before" CPU reading
#   3. Generates CPU, memory, and disk load for a short burst
#   4. Records an "after" CPU reading while load is running
#   5. Reports whether the increase was actually picked up, and reminds
#      you to check the custom alert fired in the dashboard
#
# Usage:
#   ./test_dashboard.sh [duration_seconds]
#
set -euo pipefail

NETDATA_PORT=19999
DURATION="${1:-30}"
API_BASE="http://localhost:${NETDATA_PORT}/api/v1"

log() { echo -e "\n[test_dashboard.sh] $*"; }

# ---------------------------------------------------------------------------
# 1. Confirm Netdata is reachable
# ---------------------------------------------------------------------------
if ! curl -fs "${API_BASE}/info" >/dev/null 2>&1; then
  echo "Cannot reach Netdata API at ${API_BASE}. Is it installed and running?"
  echo "Run setup.sh first, or check: systemctl status netdata"
  exit 1
fi
log "Netdata API is reachable."

get_cpu_used() {
  curl -fs "${API_BASE}/data?chart=system.cpu&after=-1&points=1&format=json" \
    | grep -o '"used":[0-9.]*' | head -1 | cut -d: -f2 || echo "0"
}

# ---------------------------------------------------------------------------
# 2. Baseline reading
# ---------------------------------------------------------------------------
sleep 2
BEFORE=$(get_cpu_used)
log "CPU usage before load: ${BEFORE:-unknown}%"

# ---------------------------------------------------------------------------
# 3. Generate load for $DURATION seconds
# ---------------------------------------------------------------------------
log "Generating CPU load across all cores for ${DURATION}s..."
CORES=$(nproc)
PIDS=()
for ((i = 0; i < CORES; i++)); do
  ( timeout "$DURATION" yes > /dev/null ) &
  PIDS+=($!)
done

log "Generating memory load (allocating/touching ~256MB)..."
( timeout "$DURATION" bash -c '
    a=()
    for i in $(seq 1 32); do
      a+=("$(head -c 8m /dev/zero | tr "\0" "x")")
      sleep 1
    done
  ' ) &
PIDS+=($!)

log "Generating disk I/O load (writing a temp file repeatedly)..."
( timeout "$DURATION" bash -c '
    while true; do
      dd if=/dev/zero of=/tmp/netdata_test_io.tmp bs=1M count=64 oflag=direct 2>/dev/null || \
      dd if=/dev/zero of=/tmp/netdata_test_io.tmp bs=1M count=64 2>/dev/null
      sleep 1
    done
  ' ) &
PIDS+=($!)

# ---------------------------------------------------------------------------
# 4. Sample CPU mid-load
# ---------------------------------------------------------------------------
sleep $(( DURATION > 6 ? 5 : DURATION / 2 ))
DURING=$(get_cpu_used)
log "CPU usage during load: ${DURING:-unknown}%"

log "Waiting for load generators to finish (up to ${DURATION}s)..."
wait "${PIDS[@]}" 2>/dev/null || true
rm -f /tmp/netdata_test_io.tmp

# ---------------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------------
log "Results:"
echo "  Before load: ${BEFORE:-unknown}%"
echo "  During load: ${DURING:-unknown}%"

if [[ -n "${BEFORE:-}" && -n "${DURING:-}" ]] && \
   awk -v b="$BEFORE" -v d="$DURING" 'BEGIN{exit !(d>b)}'; then
  echo "  -> Netdata picked up the increase in CPU usage. Monitoring is working."
else
  echo "  -> Could not confirm an increase automatically. Open the dashboard"
  echo "     and check the 'system.cpu' chart manually."
fi

echo ""
echo "Now check the dashboard for:"
echo "  - CPU/RAM/Disk I/O charts showing the spike you just generated:"
echo "    http://<server-ip>:${NETDATA_PORT}/"
echo "  - Whether the custom CPU alert (cpu_usage_high) transitioned to"
echo "    WARNING or CRITICAL, visible in the alerts panel or via:"
echo "    curl -s http://localhost:${NETDATA_PORT}/api/v1/alarms?active"
