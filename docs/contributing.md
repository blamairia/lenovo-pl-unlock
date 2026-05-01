# Contributing

Three ways to help:

## 1. Submit your laptop's working PL1/PL2 values

This is the most valuable contribution — it builds the community database that helps future users find safe defaults for their model.

### Step 1: gather system info

Save this output for the PR:

```bash
# Run this and paste output into the PR body
echo "=== Hardware ==="
echo "Vendor:  $(cat /sys/devices/virtual/dmi/id/sys_vendor)"
echo "Model:   $(cat /sys/devices/virtual/dmi/id/product_name)"
echo "Version: $(cat /sys/devices/virtual/dmi/id/product_version)"
echo "BIOS:    $(cat /sys/devices/virtual/dmi/id/bios_version) ($(cat /sys/devices/virtual/dmi/id/bios_date))"
echo ""
echo "=== CPU ==="
grep "model name" /proc/cpuinfo | head -1 | sed 's/^[^:]*: //'
echo ""
echo "=== Kernel ==="
uname -r
echo ""
echo "=== Power ==="
echo "AC: $(cat /sys/class/power_supply/ADP*/online 2>/dev/null | head -1)"
echo "Battery: $(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)%"
```

### Step 2: benchmark before+after

```bash
# At factory state (run BEFORE installing the tool, OR after):
sudo /usr/local/bin/lpl idle  # simulates factory cap
# Run Geekbench 6, save the result URL

# At your stable PL1:
sudo /usr/local/bin/lpl daily   # or whatever profile you stabilized at
# Run Geekbench 6, save the result URL
```

### Step 3: thermal verification

Run a 60-second stress test at your chosen PL1 with thermal monitoring:

```bash
yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null &
yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null &
yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null &

# In another terminal:
for i in {1..60}; do
    TEMP=$(awk '{print int($1/1000)}' /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
    PKG=$(awk -v p="$(cat /sys/class/powercap/intel-rapl:0/energy_uj)" -v PREV="${PREV:-$p}" \
        'BEGIN{print int((p-PREV)/1e6)}')
    PREV=$(cat /sys/class/powercap/intel-rapl:0/energy_uj)
    echo "T+${i}s  ${PKG}W  ${TEMP}°C"
    sleep 1
done

pkill yes
```

Note the median temp, max temp, and any thermal trips (100°C).

If max temp exceeds 100°C and you see "Throttling" entries in `dmesg`, your PL1 is too high for the chassis. Lower it.

### Step 4: open a PR

Add an entry to [`data/known-good.yml`](../data/known-good.yml). Template:

```yaml
  - dmi_product_name: "<your product_name>"
    dmi_product_version: "<your product_version>"
    cpu: "<CPU marketing name>"
    chassis: "<form factor description>"
    charger_w: <charger wattage>
    factory_pl1_linux: <observed Linux factory PL1 in W>
    factory_pl1_windows: <observed Windows factory PL1 in W, or null if untested>
    profiles:
      idle:        { pl1: 8,  pl2: 8 }
      daily:       { pl1: <stable>, pl2: <stable + 20-25> }
      performance: { pl1: <push>,   pl2: <push + 20> }
      burst:       { pl1: <max>,    pl2: <max + 30> }
    benchmarks:
      geekbench_6_factory:    "<URL>"  # e.g. 1148 / 2524
      geekbench_6_daily:      "<URL>"  # e.g. 2140 / 5877
    thermals:
      sustained_60s_all_core_pl1_<n>: "median XX°C, max XX°C"
    tested_by: "<your-github-username>"
    notes: |
      Brief notes on what works, what doesn't, any platform-specific quirks
```

PR title format: `Add <model> (<product_name>) to known-good.yml`

## 2. Improve the tool itself

Bug reports, feature requests, and code PRs welcome:

- **The autotuner** (`lpl autotune`) is currently a stub. Contributions to make it actually walk PL1 values with thermal monitoring and find the safe ceiling for each chassis would be hugely valuable.
- **Better tray app** — currently uses AppIndicator (deprecated on newer GNOME). A Qt or pure-GTK alternative would future-proof it.
- **Per-app profiles** — automatically switch to `performance` when a known compile binary launches, switch back to `daily` when idle.
- **Geekbench/PTS auto-runner** for the `lpl bench` subcommand.

## 3. Documentation

Docs PRs welcome — especially:
- Translation to other languages
- Screen-recordings of the install process
- Specific troubleshooting cases for distros we don't directly test (Fedora, Arch, NixOS)

## Code style

- Bash scripts: use `set -euo pipefail` where reasonable, `shellcheck` clean
- Python: follow PEP 8, use `python3` shebang explicitly (`/usr/bin/python3` for system-Python compat)
- YAML: 2-space indent, snake_case keys
- Markdown: GitHub Flavored, line-wrap at ~100 chars in prose, no wrap in tables/code

## Discussion

Open an issue on GitHub for questions before sending large PRs. For sensitive issues (security
concerns, etc.), contact the maintainer directly.
