#!/usr/bin/env bash
#
# setup.sh - Install and configure Netdata for basic system monitoring
#
# What this does:
#   1. Installs Netdata via the official kickstart script (non-interactive)
#   2. Confirms the service is enabled and running (CPU/RAM/disk I/O are
#      collected automatically out of the box - no config needed for that)
#   3. Adds a custom health alert: warns at 80% CPU, critical at 95%
#   4. Drops a small custom dashboard page that embeds a few charts side
#      by side (the "customize the dashboard" requirement)
#   5. Prints the URL to open in a browser
#
# Usage:
#   sudo ./setup.sh
#
set -euo pipefail

NETDATA_PORT=19999
HEALTH_DIR="/etc/netdata/health.d"
WEB_DIR="/var/lib/netdata/www"
CPU_ALERT_FILE="${HEALTH_DIR}/cpu_custom.conf"
CUSTOM_DASHBOARD_FILE="${WEB_DIR}/custom-dashboard.html"

log() { echo -e "\n[setup.sh] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "This script needs root privileges (it installs a system service)."
  echo "Re-run with: sudo ./setup.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Install Netdata (idempotent - kickstart detects existing installs)
# ---------------------------------------------------------------------------
if command -v netdata >/dev/null 2>&1; then
  log "Netdata binary already found, skipping install."
else
  log "Downloading and running the official Netdata kickstart script..."
  TMP_KICKSTART="$(mktemp)"
  wget -O "$TMP_KICKSTART" https://get.netdata.cloud/kickstart.sh
  sh "$TMP_KICKSTART" --non-interactive --stable-channel --disable-telemetry
  rm -f "$TMP_KICKSTART"
fi

# ---------------------------------------------------------------------------
# 2. Make sure the service is enabled and running
# ---------------------------------------------------------------------------
log "Enabling and starting the netdata service..."
systemctl enable --now netdata

log "Waiting for the API to come up..."
for i in {1..15}; do
  if curl -fs "http://localhost:${NETDATA_PORT}/api/v1/info" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fs "http://localhost:${NETDATA_PORT}/api/v1/info" >/dev/null 2>&1; then
  echo "Netdata does not seem to be responding on port ${NETDATA_PORT}. Check: systemctl status netdata"
  exit 1
fi
log "Netdata is up. CPU, memory, and disk I/O charts are already being collected."

# ---------------------------------------------------------------------------
# 3. Custom alert: CPU usage above 80% (warning) / 95% (critical)
# ---------------------------------------------------------------------------
log "Writing custom CPU alert to ${CPU_ALERT_FILE}..."
mkdir -p "$HEALTH_DIR"
cat > "$CPU_ALERT_FILE" <<'EOF'
# Custom alert: total CPU utilization
# Fires warning at 80%, critical at 95%, averaged over the last 10 seconds.

template: cpu_usage_high
      on: system.cpu
   class: Utilization
    type: System
component: CPU
   calc: $used
   units: %
   every: 10s
    warn: $this > 80
    crit: $this > 95
   delay: down 5m multiplier 1.5 max 1h
    info: Total CPU utilization is high
      to: sysadmin
EOF

# ---------------------------------------------------------------------------
# 4. Custom dashboard page - embeds a few charts in one simple view
# ---------------------------------------------------------------------------
log "Writing custom dashboard page to ${CUSTOM_DASHBOARD_FILE}..."
mkdir -p "$WEB_DIR"
cat > "$CUSTOM_DASHBOARD_FILE" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>My Server - Custom Monitoring View</title>
  <script type="text/javascript" src="/dashboard.js"></script>
  <style>
    body { font-family: sans-serif; background: #1a1a1a; color: #eee; margin: 20px; }
    h1 { font-weight: 300; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
  </style>
</head>
<body>
  <h1>Custom Monitoring Dashboard</h1>
  <p>A hand-picked view of the metrics I care about most, built on top of Netdata's chart API.</p>
  <div class="grid">
    <div data-netdata="system.cpu" data-title="CPU Usage" data-height="200"></div>
    <div data-netdata="system.ram" data-title="Memory Usage" data-height="200"></div>
    <div data-netdata="system.io" data-title="Disk I/O" data-height="200"></div>
    <div data-netdata="system.load" data-title="System Load" data-height="200"></div>
  </div>
</body>
</html>
EOF

log "Done."
echo "---------------------------------------------------------------"
echo " Default dashboard: http://<server-ip>:${NETDATA_PORT}/"
echo " Custom dashboard:   http://<server-ip>:${NETDATA_PORT}/custom-dashboard.html"
echo ""
echo " NOTE: the dashboard is unauthenticated by default. If this is a"
echo " public server, restrict port ${NETDATA_PORT} to your IP, e.g.:"
echo "   sudo ufw allow from <your-ip> to any port ${NETDATA_PORT}"
echo "---------------------------------------------------------------"
