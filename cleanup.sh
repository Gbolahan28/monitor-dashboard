#!/usr/bin/env bash
#
# cleanup.sh - Remove Netdata and all traces of this project's config
#
# What this does:
#   1. Stops the netdata service
#   2. Runs the official uninstaller if it's present (kickstart-based installs)
#   3. Falls back to apt purge if it was installed as a native package
#   4. Removes leftover config/data/log/cache directories
#   5. Removes our custom health alert and custom dashboard page
#
# Usage:
#   sudo ./cleanup.sh
#
set -euo pipefail

log() { echo -e "\n[cleanup.sh] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "This script needs root privileges (it removes a system service)."
  echo "Re-run with: sudo ./cleanup.sh"
  exit 1
fi

if ! command -v netdata >/dev/null 2>&1 && [[ ! -d /etc/netdata ]]; then
  log "Netdata does not appear to be installed. Nothing to do."
  exit 0
fi

log "Stopping netdata service..."
systemctl stop netdata 2>/dev/null || true
systemctl disable netdata 2>/dev/null || true

UNINSTALLER="/usr/libexec/netdata/netdata-uninstaller.sh"
if [[ -x "$UNINSTALLER" ]]; then
  log "Running official Netdata uninstaller..."
  "$UNINSTALLER" --yes --env /etc/netdata/.environment || true
elif dpkg -l 2>/dev/null | grep -q '^ii.*netdata'; then
  log "Netdata was installed via APT, purging package..."
  apt remove --purge -y netdata
else
  log "No official uninstaller found and no APT package detected."
  log "Proceeding to remove known Netdata directories manually."
fi

log "Removing leftover config, data, cache, and log directories..."
rm -rf /etc/netdata \
       /var/lib/netdata \
       /var/cache/netdata \
       /var/log/netdata \
       /opt/netdata \
       /usr/libexec/netdata

log "Removing cron/systemd auto-update leftovers..."
rm -f /etc/cron.daily/netdata-updater
rm -f /etc/cron.d/netdata-updater
systemctl disable netdata-updater.timer 2>/dev/null || true
rm -f /etc/systemd/system/netdata-updater.timer
systemctl daemon-reload 2>/dev/null || true

log "Cleanup complete. Verifying..."
if command -v netdata >/dev/null 2>&1; then
  echo "  netdata binary still found on PATH - a manual/source install may need extra cleanup."
else
  echo "  netdata binary no longer found."
fi

if [[ -d /etc/netdata ]]; then
  echo "  /etc/netdata still exists - check manually."
else
  echo "  /etc/netdata removed."
fi

echo "Done."
