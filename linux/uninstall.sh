#!/bin/bash
#
# uninstall.sh — Remove lenovo-pl-unlock from Linux
# Run with: sudo ./uninstall.sh
#

set -u

if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo: sudo ./uninstall.sh"
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "=== Stopping + disabling systemd services ==="
for svc in cpu-pl-unlock.service cpu-perf-tweaks.service lenovo-conservation-on-boot.service; do
    systemctl disable --now "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/$svc"
done
systemctl daemon-reload

echo "=== Stopping tray app ==="
for pid in $(pgrep -f "lpl-monitor.py" 2>/dev/null); do
    kill "$pid" 2>/dev/null || true
done

echo "=== Removing scripts ==="
rm -f /usr/local/bin/setPL.sh
rm -f /usr/local/bin/lpl
rm -f /usr/local/bin/lpl-set-profile
rm -f /usr/local/bin/lenovo-conservation

echo "=== Removing tray app + autostart ==="
rm -f "$TARGET_HOME/.local/bin/lpl-monitor.py"
rm -f "$TARGET_HOME/.config/autostart/lpl-monitor.desktop"

echo "=== Removing sudoers entry ==="
rm -f /etc/sudoers.d/lpl-unlock

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Uninstalled. Your CPU is back to factory throttle on next reboot."
echo "  (Until reboot, the MMIO Lock from setPL.sh is still active in"
echo "   memory; power off and on to fully revert.)"
echo "═══════════════════════════════════════════════════════════"
