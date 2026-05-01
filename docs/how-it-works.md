# How it works — the technical breakdown

This document explains exactly what's happening at the silicon, firmware, and OS layers,
and why this technique works where every other Linux unlock tool fails on consumer Lenovo
laptops.

## The problem

On a stock Lenovo IdeaPad / V / ThinkBook / Slim laptop running Linux, the CPU is throttled
to a power-limit dramatically below the chip's rated TDP — even with all standard
power-management knobs set correctly:

- `intel_pstate` driver active ✓
- `hwp_dynamic_boost = 1` ✓
- `EPP = performance` on every core ✓
- `cpupower frequency-set -g performance` ✓
- `power-profiles-daemon` set to `performance` ✓
- `/sys/firmware/acpi/platform_profile = performance` ✓
- BIOS Ultra Quiet Mode disabled ✓
- `ideapad_laptop.allow_v4_dytc=1` enabled ✓
- ACPI DYTC v4 mode commands sent (VIEP=1, MMC modes, etc.) ✓

All of these are accepted by the system. None of them lift the cap. The chip stays at ~8W,
cores stuck at 0.4-1.0 GHz under load.

## Diagnosing the throttle source

Reading Intel's `IA32_PERF_LIMIT_REASONS` register (`MSR 0x64F`) under load:

```
$ sudo rdmsr -p 0 0x64f -f 15:0
0x400
```

That's bit 10 = **Core Power Limit (CPL)**. The CPU is being told by something *outside the OS* (the EC firmware via a hardware signal line) to limit core power. This signal is:
- Asserted continuously (not transient — it's the EC's persistent policy)
- Cannot be cleared by the CPU writing to MSR 0x64F (status-only register)
- Independent of PL1/PL2 — even with PL1=27W in firmware, CPL says "actual cap is 8W"

This is the signature of an **EC-firmware-imposed current limit**. The EC is the small
microcontroller that manages low-level laptop hardware (battery, fans, keyboard, charging).
Lenovo's EC firmware on these consumer models has a policy that says "regardless of what the
OS thinks PL1 should be, throttle the CPU to ~8W via the CPL line."

## Why standard fixes don't work

| Approach | Outcome on consumer Lenovo |
|---|---|
| Write higher PL1/PL2 to MSR 0x610 | **MSR LOCKED** by BIOS — `wrmsr` returns "cannot set" |
| Write higher PL1/PL2 via `intel_rapl` sysfs | Write succeeds, value sticks, **but EC overrides via CPL** — actual chip power doesn't change |
| Clear BD_PROCHOT bit in MSR 0x1FC (ThrottleStop's classic ThinkPad fix) | **MSR LOCKED** by BIOS |
| Undervolt via OC_MAILBOX (MSR 0x150) | Write accepted but **silently rejected** — Plundervolt mitigation locked from 10th-gen Intel onwards |
| Kernel `ideapad-laptop` driver DYTC v4 commands | Accepted by EC, brief fan response, **but CPL re-asserted within seconds** |
| Direct EC register writes via debugfs (`/sys/kernel/debug/ec/ec0/io`) | Some EC bytes (FCMO at offset 0x20) ARE writable. Sweep of all 16 values yields no unlock — none control CPL |
| `throttled` (erpalma/throttled) MSR override loop | MSR 0x610 + 0x1FC both locked → **no effect**. The MCHBAR fallback writes succeed but EC overrides them |
| Patching `ideapad-laptop` to add 83A2 to DYTC v4 allowlist | The kernel module's DYTC code path doesn't reach the EC register that controls CPL |
| Newer kernel (6.13, 6.14, 6.15+) | Verified: no relevant commits in `drivers/platform/x86/lenovo/ideapad-laptop.c` since 6.12 |

## What works: the MMIO Lock technique

The trick (originally discovered by the **ThrottleStop** author for Windows) exploits a
quirk in how Intel processors arbitrate between two parallel sets of power-limit registers:

### Two paths for PL1/PL2

Modern Intel CPUs accept PL1/PL2 power limits via TWO independent registers:

1. **MSR 0x610** — CPU-internal Model-Specific Register
2. **MCHBAR offset 0x59A0** — Memory-Mapped I/O register inside the Memory Controller Hub

The CPU enforces the **lower** of the two values:
```
effective_PL1 = MIN(MSR_PL1, MCHBAR_PL1)
```

### What the EC actually does

The EC's "throttle to 8W" policy is implemented by the EC continuously writing low values to
the **MCHBAR** PL1/PL2 register (which it CAN write to via the platform firmware path). Even
if you set MSR PL1 = 45W, the MCHBAR PL1 of 8W wins because it's lower.

You CAN read MCHBAR via `/dev/mem` (with root + Secure Boot off). You can ALSO write to it.
The lock bit is at MCHBAR offset 0x59A0, bit 31.

### The trick

Two writes that flip everything:

1. **Set MSR PL1/PL2** to the desired values (e.g., 36W / 58W) — done via
   `/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_*_power_limit_uw`
2. **Write MCHBAR PL1/PL2 = 0 (no limit) AND set bit 31 (LOCK)** — done via
   `/dev/mem` mmap with `devmem2`

Result:
- MCHBAR side is now "no limit" AND locked — the EC physically cannot write to it anymore until power-off
- MSR side has our 36W limit
- `MIN(36W, ∞) = 36W` — the chip respects our limit
- The EC's CPL signal stops being asserted because the EC's "set MCHBAR low" mechanism is broken

This works because the LOCK BIT is honored by the silicon even from the EC's privileged
firmware level — once locked, the value cannot be changed in the current power-on session
by any agent, including the EC. Power-off clears the lock; the cycle starts over.

### `setPL.sh` does both writes

The `setPL.sh` script (by horshack-dpreview) automates both writes:

```bash
$ sudo ./setPL.sh 36 58
**** Current PL values from 'turbostat'
cpu0: MSR_PKG_POWER_LIMIT: 0x42828000df80d8 (UNlocked)
cpu0: PKG Limit #1: ENabled (27.000 Watts, 56 sec, clamp ENabled)
cpu0: PKG Limit #2: ENabled (80.000 Watts, 0.002 sec, clamp DISabled)
**** Setting PL1=36000000 and PL2=58000000 in /sys/class/powercap/...
**** PL1 and PL2 already enabled in MSR_PKG_POWER_LIMIT
**** New PL values from 'turbostat'
cpu0: PKG Limit #1: ENabled (36.000 Watts, 56 sec, clamp ENabled)
cpu0: PKG Limit #2: ENabled (58.000 Watts, 0.002 sec, clamp DISabled)
**** MCHBAR is 0xfedc0001
**** Current value of PACKAGE_RAPL_LIMIT_0_0_0_MCHBAR_PCU = 0x00428280:0x42828000df8040
**** Setting PACKAGE_RAPL_LIMIT_0_0_0_MCHBAR_PCU = 0x80000000:0x00000000
                                                  ^^^^^^^^^^^^^^^^^^^
                                                  bit 31 = LOCK BIT
```

## PL1 time window — the second knob

By default, the Linux RAPL driver sets PL1's time window to **56 seconds**. This means PL1
only kicks in after 56 seconds of sustained high power. Within that window, the chip can
draw up to PL2 (boost limit).

For chassis with limited cooling, this is dangerous — the chip pulls 50+W for a full minute
before the OS even tries to limit it, by which time temps are at 100°C and the chip
self-throttles or shuts down.

We override the time window to **1 second** so PL1 takes effect immediately:

```bash
echo 1000000 > /sys/class/powercap/intel-rapl:0/constraint_0_time_window_us
```

This is what makes profiles like `lpl daily` (PL1=36W) sustain at 36W with stable temps,
instead of bouncing between 50W and thermal-throttle.

## Why the lock works (silicon-level)

The MCHBAR lock bit is implemented in the Power Control Unit (PCU) firmware, which is part
of the CPU silicon (not the EC). When the lock bit is set:

- The PCU's internal arbitration accepts no further writes to that register
- The EC's writes to MCHBAR PL1/PL2 are silently dropped
- The MCHBAR register effectively becomes read-only until the chip loses power

This is the same lock semantics Intel uses for security-critical registers (e.g.,
`IA32_FEATURE_CONTROL`). It's by-spec behavior, not an exploit. We just use it for our own
purposes instead of leaving it unset for the EC to reconfigure.

## Why every reboot needs to re-apply

The MCHBAR lock is "until power off" — it survives reboots only if you don't fully power
down. After a true power cycle (or even a long suspend on some platforms), the lock clears
and the EC reasserts factory throttle on next boot.

That's why this tool installs a `systemd` service that re-runs `setPL.sh` on every boot —
to re-apply the lock before any high-load workload would notice the throttle is back.

## What about the chip's own protection?

The MMIO Lock only disables the EC's **firmware-level** throttle. The CPU's hardware-level
thermal protection (TJ-max trip at 100°C, then catastrophic at 105°C) is implemented in the
silicon and **always works**. If you set PL1 too high for your chassis, the chip will hit
its trip point and clean-shutdown — no damage. We saw this happen during testing at PL1=45W
on a thin chassis.

That's why `lpl autotune` (planned) sweeps PL1 values while monitoring CPU temperature, to
find the highest stable value for THIS chassis before declaring a "default" profile.

## Why this is OK to ship

Some users worry this is "overclocking" or "modifying" the BIOS. It's neither:

- **No BIOS change.** No flashing, no setup_var, no NVRAM write. The BIOS is identical.
- **No silicon modification.** The CPU runs within its rated TDP and rated voltage. We
  simply remove the artificial firmware-imposed cap that's BELOW the chip's rated specs.
- **Reversible at next power-off.** If you don't run `setPL.sh`, the EC's factory cap
  reasserts. You can't permanently change anything.
- **The CPU's hardware safety still works.** Thermal trip = clean shutdown. No way to damage
  silicon from this technique alone.

The only thing this tool changes is **a runtime firmware policy** that Lenovo applies for
arguable reasons (fan noise, battery longevity, maybe yield management). On a desktop chip
or ThinkPad you'd already have access to the same capability — Lenovo just chose to lock it
on consumer mobile lines.
