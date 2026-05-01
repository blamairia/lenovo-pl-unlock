# Changelog

## v0.1.0 — Initial release

First public release. Working unlock for Lenovo V17 G4 IRU (model 83A2, i5-13420H).

### Linux

- `lpl` CLI with profiles: idle, daily, performance, burst
- `lpl-monitor.py` system tray app with live wattage, profile switcher, conservation toggle
- `setPL.sh` integration (vendored from horshack-dpreview/setPL)
- systemd services for boot persistence:
  - `cpu-pl-unlock.service` — applies MMIO Lock + PL1/PL2 on boot
  - `cpu-perf-tweaks.service` — HWP boost, EPP=performance, RAPL perms
  - `lenovo-conservation-on-boot.service` — battery cap at 60% (optional)
- Sudoers NOPASSWD config for unprivileged profile switching
- Tested on Debian 13, kernel 6.12.74

### Windows

- ThrottleStop configuration documentation with EXACT settings for the unlock
- PowerShell `install.ps1` to set up Task Scheduler auto-launch on boot
- Documentation of Windows-side optimizations (Power Plan, Vantage tier, Defender exclusions)

### Documentation

- `README.md` — overview + benchmark table
- `docs/how-it-works.md` — full technical breakdown of the MMIO Lock technique
- `docs/supported-models.md` — community-tested models
- `docs/contributing.md` — how to submit your model's data
- `benchmarks/geekbench-results.md` — full Geekbench 6 numbers across 5 PL1 levels

### Known issues

- `lpl autotune` is a planned stub — for now use the V17 G4 defaults or the chassis-specific values in `data/known-good.yml`
- The tray app uses deprecated `libayatana-appindicator` — works on current GNOME 48 with the AppIndicator extension but may need migration on future GNOME versions
- Single test platform — V17 G4. Other Lenovo consumer laptops likely work but need community testing
