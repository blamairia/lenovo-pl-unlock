# Supported / tested models

The community-contributed list lives in machine-readable form at [`data/known-good.yml`](../data/known-good.yml). This page is its human-readable summary.

## Directly tested

| Model | Product code | CPU | Charger | Factory PL1 | Recommended PL1 | Speedup |
|---|---|---|---|---|---|---|
| Lenovo V17 G4 IRU | `83A2` | i5-13420H | 65 W | 8 W (Linux) / 20 W (Windows) | **36 W** | **2.6×** GB6 multi-core |

## Likely compatible (untested but follow same EC pattern)

The MMIO Lock technique works on any Intel-based Lenovo laptop where:
1. The CPU has rated TDP > the firmware-imposed cap
2. BIOS does NOT lock MCHBAR (most consumer Lenovo BIOSes do not lock MCHBAR — only MSR)
3. Secure Boot is disabled (required for `/dev/mem` access)

These laptop families *generally* match the criteria. If you have one and try the tool, please submit your results:

- IdeaPad Slim 5 (any 14"/16" with H-series CPU) — the model that started this whole research
- IdeaPad 5 / 5 Pro
- IdeaPad Gaming 3 / Gaming 5
- ThinkBook 14 / 16 / Plus G4+
- V14 / V15 / V17 series
- Lenovo Slim 7 / Slim Pro

**Likely NOT compatible:**
- ThinkPad T-series and X-series — these mostly don't have the EC throttle issue (different firmware)
- Legion series — has its own ecosystem ([LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux))
- Yoga 9-series — Intel Evo certified, less aggressive throttling out of box
- Desktop motherboards — no EC throttling

## How to test on your laptop

```bash
# 1. Verify your platform has the throttle pattern
sudo apt install msr-tools
sudo modprobe msr

# Run any heavy load in another terminal:
yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null &

# Check if the EC is asserting CPL:
sudo rdmsr -p 0 0x64f -f 15:0
# If 0x400 → CPL is asserted, this tool will help you
# If 0x000 → no EC throttle, you don't need this tool

# Cleanup:
pkill yes

# 2. Install the tool
git clone https://github.com/blamairia/lenovo-pl-unlock.git
cd lenovo-pl-unlock/linux
sudo ./install.sh

# 3. Try the daily profile and verify
sudo lpl daily
lpl status

# 4. Run benchmarks and submit a PR
# See docs/contributing.md
```

## Submitting your model

PRs welcome. See [contributing.md](contributing.md) for the template.

Minimum required:
- Model identification (`/sys/devices/virtual/dmi/id/{product_name,product_version,sys_vendor}`)
- CPU model (`grep "model name" /proc/cpuinfo | head -1`)
- Charger wattage (e.g., 65W barrel jack, 100W USB-C, etc.)
- Geekbench 6 result URL at factory state
- Geekbench 6 result URL at your stable PL1 setting
- Max sustained temp during 60-sec stress test at your PL1
- Tested kernel version

This data feeds into `lpl autotune --suggest` which will propose a starting PL1 based on your laptop model match.
