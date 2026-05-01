# lenovo-pl-unlock

**Unlock the H-series CPU performance Lenovo locks away on consumer IdeaPad / V / ThinkBook / Slim laptops — on both Linux and Windows.**

## The problem

Lenovo ships consumer laptops (IdeaPad, V-series, ThinkBook, Slim) with H-series Intel CPUs that are **artificially throttled by the Embedded Controller (EC) firmware** below the chip's rated TDP. On Linux specifically, this is **catastrophically worse** than on Windows because Lenovo never released a Linux equivalent of `Lenovo Vantage`, which on Windows runtime-manages the EC.

**Real example — Lenovo V17 G4 IRU (model 83A2), Intel i5-13420H (45 W rated TDP):**

| State | PL1 sustained | % of rated TDP | Multi-core Geekbench 6 | All-core freq under load |
|---|---|---|---|---|
| **Linux factory (out of box)** | **8 W** | **18%** | **2,524** | 0.4 – 1.0 GHz |
| Windows factory + **Lenovo Vantage "Performance Mode"** | 20 W | **44%** | 5,409 | 2.0 – 2.5 GHz |
| `lpl unlock` daily mode | 36 W | 80% | 5,877 | 3.5 – 4.0 GHz |
| `lpl unlock --aggressive` | 45 W | **100%** | 6,251 | 3.7 – 4.0 GHz |
| Chip spec maximum | 60 W | 133% | **6,539** | 4.0 – 4.5 GHz |

That's a **2.6× multi-core speedup** vs Linux factory state — and crucially, **Lenovo Vantage's "Performance Mode" still only delivers 44% of the chip's rated TDP**. Vantage is not a fix; it just makes the throttle slightly less catastrophic. The actual unlock requires the MMIO Lock technique — ThrottleStop on Windows, this tool on Linux.

The chip has been the same all along. Lenovo just wouldn't let you use it.

## How it works

This tool uses the **MMIO Lock technique** (the same one Windows users apply via [ThrottleStop](https://www.techpowerup.com/download/techpowerup-throttlestop/)):

1. Sets PL1/PL2 power limits in both MSR (Model-Specific Register) and MCHBAR (Memory-Mapped I/O register at offset 0x59A0)
2. **Sets the lock bit in the MMIO register** so the EC firmware cannot reset it back to factory defaults
3. Once locked, only the MSR limits apply, and they stay at our requested values until power-off

Without the MMIO lock, Lenovo's EC firmware reasserts the conservative limits every few seconds, dragging the CPU back to 8W. The lock is the "secret sauce."

Credit: the technique was discovered by the [ThrottleStop](https://www.techpowerup.com/download/techpowerup-throttlestop/) author for Windows. The `setPL.sh` script that this tool wraps was written by [horshack-dpreview](https://github.com/horshack-dpreview/setPL) for Linux.

## Quick start

### Linux (Debian/Ubuntu/Arch)

```bash
git clone https://github.com/blamairia/lenovo-pl-unlock.git
cd lenovo-pl-unlock/linux
sudo ./install.sh
```

After installation, the unlock applies on every boot. Use the CLI to switch profiles:

```bash
sudo lpl daily         # 36W sustained — recommended for most use
sudo lpl performance   # 45W sustained — heavy load
sudo lpl burst         # 60W/90W — short benchmark bursts
sudo lpl idle          # 8W — factory throttle (battery-friendly)
sudo lpl status        # show current profile + live wattage
```

A system tray app is also installed (`lpl-monitor`) showing live wattage, frequency, and a profile switcher.

### Windows

See [windows/README.md](windows/README.md). The Windows side is automated using [ThrottleStop](https://www.techpowerup.com/download/techpowerup-throttlestop/) + a Task Scheduler auto-launch — no custom drivers needed.

## Supported models

We've directly tested:

| Model | DMI Product | CPU | Recommended PL1 | Notes |
|---|---|---|---|---|
| Lenovo V17 G4 IRU | `83A2` | i5-13420H | 36 W | Tested, stable |

This technique should work on any modern Intel-based Lenovo IdeaPad / V / ThinkBook / Slim that exhibits the EC throttle pattern. **Submit your model's results via PR to [`data/known-good.yml`](data/known-good.yml)** — see [contributing](#contributing) below.

## Documentation

- **[How it works](docs/how-it-works.md)** — the full technical explanation: CPL bit, MMIO Lock, time windows, why factory was 8W
- **[Supported models](docs/supported-models.md)** — community-contributed safe defaults per laptop model
- **[Benchmarks](benchmarks/geekbench-results.md)** — full Geekbench 6 results (5 PL1 levels, public Geekbench Browser URLs)
- **[Linux side](linux/README.md)** — install, uninstall, CLI reference, systemd unit details
- **[Windows side](windows/README.md)** — ThrottleStop config + Task Scheduler auto-launch

## Safety / disclaimer

- **No BIOS modding.** All modifications are reversible at the OS layer — power off, settings revert.
- **The chip's own thermal protection still works.** If you set PL1 too high for your chassis, the CPU will hit its 100°C trip point and shut down cleanly to protect itself. This is normal hardware behavior, not damage.
- **Use sensible PL1 values for your chassis.** The defaults here (36 W for V17 G4) were found via the included autotuner with thermal monitoring. Don't run PL1=60 W as a daily setting on thin chassis.
- **65 W charger is the practical wall power ceiling** for most Lenovo consumer laptops. Brief PL2 bursts can pull from battery; sustained beyond charger spec is not advisable.

We've extensively tested the Linux side on a Lenovo V17 G4. We do not warrant any other hardware, and obviously this voids any "warranty" Lenovo might offer (in practice they only warranty against hardware defects, not software performance, so functionally there's no risk to your warranty — the lock is removed at next power-off).

## Contributing

If you have a different Lenovo IdeaPad / V / ThinkBook / Slim and want to contribute:

1. Run `sudo linux/lpl autotune` — it discovers safe PL1 for your chassis
2. Run `linux/lpl bench` — captures Geekbench / 7z / sysbench numbers before+after
3. Submit a PR adding your entry to [`data/known-good.yml`](data/known-good.yml)

See [docs/contributing.md](docs/contributing.md) for the full template.

## Why this exists

Modern consumer laptops increasingly turn capable hardware into capped, vendor-controlled appliances. You buy an "H-series 45W TDP" CPU and the manufacturer ships it limited to 8W on Linux because their proprietary tooling doesn't run there. That's not "by design," that's neglect — and it turns hardware into expensive e-waste before its time.

This tool exists to give Linux users the same access Windows users have via ThrottleStop. If Lenovo eventually ships proper Linux support, this tool becomes unnecessary. Until then, here we are.

## License

MIT. See [LICENSE](LICENSE).

`setPL.sh` is included from [horshack-dpreview/setPL](https://github.com/horshack-dpreview/setPL) under MIT.

## Credits

- [horshack-dpreview/setPL](https://github.com/horshack-dpreview/setPL) — the underlying MMIO lock script for Linux
- The ThrottleStop author — for discovering the MMIO Lock technique on Windows
- Hans de Goede / Ike Panhc — kernel `ideapad-laptop` driver maintainers (the partial DYTC v4 work)
