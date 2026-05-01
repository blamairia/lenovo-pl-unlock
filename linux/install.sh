#!/bin/bash
#
# install.sh — Install lenovo-pl-unlock on Linux
#
# What this does:
#   1. Installs setPL.sh, lpl, lpl-set-profile, lenovo-conservation to /usr/local/bin
#   2. Installs lpl-monitor.py (tray app) to ~/.local/bin
#   3. Installs systemd services (cpu-pl-unlock, cpu-perf-tweaks, lenovo-conservation-on-boot)
#   4. Adds NOPASSWD sudoers entry for billell to call lpl-set-profile and lenovo-conservation
#   5. Sets up tray app autostart .desktop entry
#   6. Installs build deps (devmem2 + msr-tools + linux-cpupower)
#
# Run with: sudo ./install.sh
#

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo: sudo ./install.sh"
    exit 1
fi

# Find the user invoking sudo (so we install tray autostart for them, not root)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    echo "Cannot determine non-root user home directory. Re-run with: sudo -u <user> ./install.sh"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Installing from: $REPO_DIR"
echo "Target user: $TARGET_USER (home: $TARGET_HOME)"
echo ""

echo "=== 1. Install dependencies ==="
if command -v apt &>/dev/null; then
    apt update -qq
    apt install -y msr-tools linux-cpupower build-essential
    if ! command -v devmem2 &>/dev/null; then
        echo "    Building devmem2 from source (not in apt repos)..."
        TMPD=$(mktemp -d)
        curl -sL https://raw.githubusercontent.com/blamairia/lenovo-pl-unlock/main/linux/devmem2.c -o "$TMPD/devmem2.c" 2>/dev/null || \
        curl -sL https://github.com/raspberrypi/utils/raw/master/raspi-config/raspi-config -o "$TMPD/devmem2.c" 2>/dev/null || true
        # Fallback: write devmem2.c inline
        cat > "$TMPD/devmem2.c" <<'EOF_DEVMEM2'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <ctype.h>
#include <sys/mman.h>
#define MAP_SIZE 4096UL
#define MAP_MASK (MAP_SIZE - 1)
int main(int argc, char **argv) {
    int fd; void *map_base, *virt_addr;
    unsigned long read_result, writeval; off_t target;
    int access_type = 'w';
    if (argc < 2) { fprintf(stderr,"Usage: %s ADDR [b|h|w] [DATA]\n",argv[0]); exit(1); }
    target = strtoul(argv[1], 0, 0);
    if (argc > 2) access_type = tolower(argv[2][0]);
    if ((fd = open("/dev/mem", O_RDWR | O_SYNC)) == -1) { perror("/dev/mem"); exit(1); }
    map_base = mmap(0, MAP_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, target & ~MAP_MASK);
    if (map_base == MAP_FAILED) { perror("mmap"); exit(1); }
    virt_addr = (char*)map_base + (target & MAP_MASK);
    switch (access_type) {
        case 'b': read_result = *((unsigned char*)virt_addr); break;
        case 'h': read_result = *((unsigned short*)virt_addr); break;
        case 'w': read_result = *((unsigned long*)virt_addr); break;
        default: fprintf(stderr,"Bad type\n"); exit(2);
    }
    printf("Value at address 0x%lX (%p): 0x%lX\n", target, virt_addr, read_result);
    if (argc > 3) {
        writeval = strtoul(argv[3], 0, 0);
        switch (access_type) {
            case 'b': *((unsigned char*)virt_addr) = writeval; read_result = *((unsigned char*)virt_addr); break;
            case 'h': *((unsigned short*)virt_addr) = writeval; read_result = *((unsigned short*)virt_addr); break;
            case 'w': *((unsigned long*)virt_addr) = writeval; read_result = *((unsigned long*)virt_addr); break;
        }
        printf("Written 0x%lX; readback 0x%lX\n", writeval, read_result);
    }
    munmap(map_base, MAP_SIZE); close(fd); return 0;
}
EOF_DEVMEM2
        gcc -O2 -o "$TMPD/devmem2" "$TMPD/devmem2.c"
        install -m 0755 "$TMPD/devmem2" /usr/local/bin/devmem2
        rm -rf "$TMPD"
    fi
elif command -v pacman &>/dev/null; then
    pacman -S --needed --noconfirm msr-tools linux-tools-meta base-devel
    # Arch typically has devmem2 in AUR; print hint
    if ! command -v devmem2 &>/dev/null; then
        echo "    devmem2 not found. Install via AUR: yay -S devmem2"
        exit 1
    fi
fi

echo ""
echo "=== 2. Install scripts to /usr/local/bin ==="
install -m 0755 "$REPO_DIR/setPL.sh"             /usr/local/bin/setPL.sh
install -m 0755 "$REPO_DIR/lpl"                  /usr/local/bin/lpl
install -m 0755 "$REPO_DIR/lpl-set-profile"      /usr/local/bin/lpl-set-profile
install -m 0755 "$REPO_DIR/lenovo-conservation"  /usr/local/bin/lenovo-conservation
echo "   ✓ /usr/local/bin/{setPL.sh,lpl,lpl-set-profile,lenovo-conservation}"

echo ""
echo "=== 3. Install tray app to ~/.local/bin ==="
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.local/bin"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 \
    "$REPO_DIR/lpl-monitor.py" "$TARGET_HOME/.local/bin/lpl-monitor.py"
echo "   ✓ $TARGET_HOME/.local/bin/lpl-monitor.py"

echo ""
echo "=== 4. Install systemd services ==="
install -m 0644 "$REPO_DIR/systemd/cpu-pl-unlock.service"           /etc/systemd/system/
install -m 0644 "$REPO_DIR/systemd/cpu-perf-tweaks.service"          /etc/systemd/system/
install -m 0644 "$REPO_DIR/systemd/lenovo-conservation-on-boot.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cpu-pl-unlock.service
systemctl enable --now cpu-perf-tweaks.service
# Conservation: only enable if user wants — skip auto-enable
echo "   ✓ cpu-pl-unlock.service:        $(systemctl is-active cpu-pl-unlock.service)"
echo "   ✓ cpu-perf-tweaks.service:      $(systemctl is-active cpu-perf-tweaks.service)"
echo "     lenovo-conservation-on-boot:  installed but NOT enabled by default"
echo "     → enable with: sudo systemctl enable --now lenovo-conservation-on-boot"

echo ""
echo "=== 5. Install sudoers NOPASSWD entries ==="
cat > /etc/sudoers.d/lpl-unlock <<EOF
$TARGET_USER ALL=(root) NOPASSWD: /usr/local/bin/lpl-set-profile
$TARGET_USER ALL=(root) NOPASSWD: /usr/local/bin/lenovo-conservation
EOF
chmod 0440 /etc/sudoers.d/lpl-unlock
echo "   ✓ /etc/sudoers.d/lpl-unlock — $TARGET_USER can switch profiles + toggle conservation without password prompt"

echo ""
echo "=== 6. Install tray app autostart ==="
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.config/autostart"
cat > "$TARGET_HOME/.config/autostart/lpl-monitor.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=LPL Monitor
Comment=Lenovo PL Unlock — live wattage tray + profile switcher
Exec=/usr/bin/python3 $TARGET_HOME/.local/bin/lpl-monitor.py
Icon=power-profile-performance-symbolic
Terminal=false
Categories=System;Monitor;
X-GNOME-Autostart-enabled=true
StartupNotify=false
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart/lpl-monitor.desktop"
echo "   ✓ Tray autostart entry installed"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Installation complete"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Current state:"
sudo -u "$TARGET_USER" /usr/local/bin/lpl status 2>/dev/null || /usr/local/bin/lpl status
echo ""
echo "  Switch profiles with:   sudo lpl <idle|daily|performance|burst>"
echo "  Show status with:       lpl status"
echo "  Tray app:               will autostart on next login (or run now: lpl-monitor.py &)"
echo "  Uninstall:              sudo lpl uninstall"
