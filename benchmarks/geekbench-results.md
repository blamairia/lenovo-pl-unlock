# Benchmarks — Lenovo V17 G4 IRU (model 83A2), Intel i5-13420H

All runs on the same machine, same Debian 13 install, same kernel `6.12.74+deb13+1-amd64`,
same temperature room conditions, same dev workload background (none — clean state).

## Geekbench 6.7.1

| Run | PL1 (W) | PL2 (W) | Single-Core | Multi-Core | Run time | Result URL |
|---|---|---|---|---|---|---|
| 1 — Linux factory simulation | 8 | 8 | **1148** | **2524** | ~9 min | [17839210](https://browser.geekbench.com/v6/cpu/17839210) |
| 2 — Windows factory simulation | 20 | 50 | 2113 | 5409 | ~5 min | [17839071](https://browser.geekbench.com/v6/cpu/17839071) |
| 3 — `lpl daily` | 36 | 58 | 2140 | 5877 | ~5 min | [17838715](https://browser.geekbench.com/v6/cpu/17838715) |
| 4 — `lpl performance` | 45 | 65 | 2204 | 6251 | ~5 min | [17838772](https://browser.geekbench.com/v6/cpu/17838772) |
| 5 — `lpl burst` | 60 | 90 | 2166 | **6539** | ~5 min | [17838843](https://browser.geekbench.com/v6/cpu/17838843) |

## Speedup vs Linux factory state

| Profile | Single-Core ratio | Multi-Core ratio |
|---|---|---|
| `lpl idle` | 1.00× (baseline) | 1.00× (baseline) |
| `lpl daily` | **1.86×** | **2.33×** |
| `lpl performance` | 1.92× | 2.48× |
| `lpl burst` | 1.89× | **2.59×** |

## Observations

1. **Single-core saturates around PL1=20W** — once one core can boost to 4.6 GHz turbo within budget, more PL1 budget doesn't help single-thread perf. The Single-Core differences between PL1=20W and PL1=60W are within run-to-run variance.

2. **Multi-core scales monotonically with PL1** up to PL1=60W, but with diminishing returns:
   - PL1=8 → PL1=20: +114% multi (8W cap was strangling all 12 threads)
   - PL1=20 → PL1=36: +8.7% multi
   - PL1=36 → PL1=45: +6.4% multi
   - PL1=45 → PL1=60: +4.6% multi

3. **PL1=8W run took ~9 minutes** — 80% slower than unlocked runs. Even Geekbench's bursty workload couldn't escape the 8W cap.

4. **Single-core score 1148 at PL1=8W** is roughly half of PL1=36W (2140). At 8W the chip can't even sustain a single-thread boost — confirming the cap was strangling EVERYTHING, not just multi-thread.

## What "8W on Linux factory" means in practice

- 12 threads × 0.7W per thread average
- Cores stuck at 0.4-1.0 GHz under any load
- Typing in a terminal had visible 30-50ms lag (kernel logged "client bug: event processing lagging behind")
- A 2024-era H-series chip was performing slower than a 2010 ULV laptop

## How these were captured

```bash
# 1. Apply target PL1/PL2 via setPL.sh (this tool's wrapper)
sudo /usr/local/bin/setPL.sh <PL1> <PL2>
echo 1000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_0_time_window_us

# 2. Verify state
lpl status

# 3. Run Geekbench (downloaded from primatelabs.com)
cd ~/Downloads/Geekbench-6.7.1-Linux
./geekbench6
```

The result URL is uploaded to browser.geekbench.com automatically. Results are publicly
viewable and shareable; anyone can verify the system info, scores, and per-test breakdowns.

## Comparison with reviewed laptops

Laptop reviews of the i5-13420H typically show Geekbench 6 multi-core in the **8,500–11,000** range, depending on the laptop's TDP configuration:
- Slim 14"/15" laptops with 25W PL1: ~7,500-9,000
- Performance laptops with 35W PL1: ~10,000+
- High-TDP unlocked configs: 12,000+

Our V17 G4 unlocked to PL1=60W achieves **6,539 multi-core** — below typical review numbers because:
- The 17" V-series chassis still thermally caps sustained loads
- The 65W charger is a hard wall power ceiling
- The chip-spec configurable TDP for i5-13420H tops at 95W turbo, but sustained
  thermal envelope is limited by the cooler (which Lenovo dimensioned for 20W operation)

But compared to the **2,524 multi-core at Linux factory state**, we recovered **159% of the multi-core performance** that Lenovo's firmware was hiding from us.

## Stress / sustained workload (separate from Geekbench)

Tested with 12 threads of `yes > /dev/null` for 60 seconds at each profile:

| Profile | Avg pkg power | Avg all-core freq | Median CPU temp | Max CPU temp |
|---|---|---|---|---|
| idle (PL1=8) | 7.6 W | 0.5 GHz | 56 °C | 60 °C |
| daily (PL1=36) | 33.4 W | 2.77 GHz | 86 °C | 97 °C |
| performance (PL1=45) | 36.5 W | 2.83 GHz | 85 °C | 100 °C (rare trip) |
| burst (PL1=60) | unstable — chip oscillates between 23-46W due to thermal throttle |

**Conclusion**: PL1=36W is the sustained sweet spot for this chassis. PL1=45W is borderline. PL1=60W is benchmark-only.
