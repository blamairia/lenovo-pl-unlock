# Linux side — lenovo-pl-unlock

## Install

```bash
git clone https://github.com/blamairia/lenovo-pl-unlock.git
cd lenovo-pl-unlock/linux
sudo ./install.sh
```

The installer:
- Builds & installs `devmem2` (needed for MMIO writes), msr-tools, linux-cpupower
- Installs `lpl`, `setPL.sh`, `lpl-set-profile`, `lenovo-conservation` to `/usr/local/bin`
- Installs `lpl-monitor.py` (system tray) to `~/.local/bin`
- Installs and enables systemd services: `cpu-pl-unlock`, `cpu-perf-tweaks`
- Adds NOPASSWD sudoers entries so the tray can switch profiles without password prompts
- Installs tray autostart `.desktop` entry

## CLI usage

```bash
sudo lpl daily         # PL1=36W PL2=58W — recommended for most use
sudo lpl performance   # PL1=45W PL2=65W — heavy sustained load
sudo lpl burst         # PL1=60W PL2=90W — short benchmark bursts
sudo lpl idle          # PL1=8W   PL2=8W  — factory throttle (battery)

lpl status             # Show current profile + live wattage + freq
lpl current            # Print just the current profile name
sudo lpl install       # Re-run installer
sudo lpl uninstall     # Remove everything
```

## Tray app

After install, on next login you'll see a `⚡ X.XW` indicator in your system tray.
Click it for:
- Live power, frequency, CPU% readouts (refreshed every 2 sec)
- Power profile switcher (performance / balanced / power-saver)
- LPL mode switcher (idle / daily / performance / burst) — **switches PL1/PL2 instantly, no password prompt**
- Battery conservation toggle (cap charge at 60% — Lenovo's lifespan-preservation mode)

To launch manually: `python3 ~/.local/bin/lpl-monitor.py &`

Requires `gir1.2-ayatanaappindicator3-0.1` and a panel that displays AppIndicator items
(GNOME with the AppIndicator extension enabled, KDE Plasma, MATE, Cinnamon, etc.).

## Systemd services

| Service | What it does | Boot order |
|---|---|---|
| `cpu-pl-unlock.service` | Runs `setPL.sh 36 58`, sets PL1 time window to 1s, applies MMIO Lock | After multi-user.target |
| `cpu-perf-tweaks.service` | Sets `hwp_dynamic_boost=1`, EPP=performance on every core, makes RAPL energy_uj world-readable, applies GNOME power-profile=performance | After multi-user.target |
| `lenovo-conservation-on-boot.service` | Forces battery conservation_mode=1 (cap at 60%) — installed but disabled by default | – |

To enable battery conservation auto-on-boot:
```bash
sudo systemctl enable --now lenovo-conservation-on-boot.service
```

## Files installed

| Path | What |
|---|---|
| `/usr/local/bin/setPL.sh` | The MMIO-lock unlock script (from horshack-dpreview/setPL) |
| `/usr/local/bin/lpl` | Main CLI |
| `/usr/local/bin/lpl-set-profile` | Helper invoked by tray app via sudoers NOPASSWD |
| `/usr/local/bin/lenovo-conservation` | Helper for conservation_mode toggle |
| `/etc/systemd/system/cpu-pl-unlock.service` | Boot persistence for PL1/PL2 |
| `/etc/systemd/system/cpu-perf-tweaks.service` | Boot persistence for HWP/EPP/perms |
| `/etc/systemd/system/lenovo-conservation-on-boot.service` | Optional battery cap on boot |
| `/etc/sudoers.d/lpl-unlock` | NOPASSWD for the helper scripts |
| `~/.local/bin/lpl-monitor.py` | GTK tray app |
| `~/.config/autostart/lpl-monitor.desktop` | Tray autostart entry |

## Uninstall

```bash
sudo lpl uninstall
# Or:
cd lenovo-pl-unlock/linux && sudo ./uninstall.sh
```

This stops services, removes all installed files, and reverts your CPU to factory
throttle on next reboot. (Until reboot, the MMIO Lock is still active — only a full
power-off clears it.)

## Troubleshooting

**`lpl status` shows PL1=8W after reboot:**
- `sudo systemctl status cpu-pl-unlock.service` — check if the service started
- `sudo journalctl -u cpu-pl-unlock.service --no-pager -n 20` — see why it failed
- Most common cause: `setPL.sh` not in `/usr/local/bin` or `devmem2` missing

**Tray icon doesn't appear:**
- Verify AppIndicator support extension is enabled (GNOME): `gnome-extensions list --enabled | grep -i indicator`
- Check the tray app log: `tail /tmp/lpl-monitor.log` (or the systemd user journal)
- Run manually for debug: `python3 ~/.local/bin/lpl-monitor.py`

**Profile switch from tray asks for password:**
- The `/etc/sudoers.d/lpl-unlock` file may have wrong permissions
- Should be `0440` and owned by `root:root`
- Verify with `sudo -n /usr/local/bin/lpl-set-profile current` — should print profile without prompt

**Setting PL1 too high → laptop suddenly shuts down:**
- That's the CPU's hardware thermal protection (100°C trip). Normal and safe.
- Lower your PL1 setting. For thin/14"/16" chassis, 30-40W is the practical sustained max.
- Reboot, switch back to a lower profile (`sudo lpl daily`).

## How the unlock works

See [`docs/how-it-works.md`](../docs/how-it-works.md) for the full technical breakdown:
- The CPL bit (MSR 0x64F bit 10) — what the EC asserts to throttle
- MSR vs MCHBAR — two paths for power limits, both writable but with different lock semantics
- The MMIO Lock technique — why setting MMIO PL1/PL2 to 0 + lock bit = the EC can no longer override
- PL1 time window — why we set it to 1 second (vs Linux default 56 seconds)
