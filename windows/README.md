# Windows side — ThrottleStop + Auto-launch

The Windows approach uses **ThrottleStop** to apply the MMIO Lock + PL1/PL2 unlock, and **Task Scheduler** to auto-launch ThrottleStop with your saved profile on every boot.

> Why ThrottleStop and not a custom app? ThrottleStop is a 15-year-old battle-tested tool used by hundreds of thousands of laptop users. Replicating it would require a signed kernel-mode driver (WinRing0 or similar) — months of work for marginal gain. ThrottleStop is free and works.

## One-time setup (5 minutes)

### Step 1 — Install ThrottleStop

1. Download from [TechPowerUp](https://www.techpowerup.com/download/techpowerup-throttlestop/)
2. Extract to `C:\Program Files\ThrottleStop\` (any path works, but be consistent)

### Step 2 — Configure ThrottleStop (the EXACT settings that matter)

Run ThrottleStop as admin. Apply the following — **do not skip any of these**, the unlock depends on them.

#### Main window
- ☑ **Speed Shift** → set value to **0** (max performance)
- ☐ **BD PROCHOT** (uncheck — when checked, EC can still throttle bidirectionally)
- Profile dropdown → select profile slot (e.g., "Performance"), name it "V17-Unlock"

#### Click **TPL** button (Turbo Power Limits window)

**MMIO section** — *this is the critical part*
- ☑ **Lock** — prevents EC from resetting your power limits
- ☑ **Sync MMIO** — keeps MMIO and MSR in sync
- Long Power PL1: **60** (or 45 for cooler operation)
- Short Power PL2: **90** (or 65 for charger-safe)
- ☑ **Clamp** (PL1)
- Turbo Time Limit: **127** (slide all the way right)

**Other**
- Speed Shift Min: 0
- Speed Shift Max: 0 (some prefer 47 for 4.7GHz max — leave 0 for auto)
- Power Limit 4: **0**
- PP0 Power Limit: **0**, ☐ unchecked

Click **OK**.

#### Click **FIVR** button (if you want to verify undervolt isn't the issue)
- Note: 13th-gen Intel chips have **Plundervolt mitigation** locked, so undervolt won't take. Skip the voltage offsets — they'll appear to apply but the CPU rejects them silently.

#### Save the profile
- Back in main window: **Options** → ☑ **Save as default**
- Or use the profile slot system and ensure your "V17-Unlock" profile loads on launch

### Step 3 — Verify the unlock works

1. Open Task Manager → Performance → CPU
2. Run any moderate load (open Chrome with a few tabs, or run a quick Geekbench Single-Core)
3. Watch the **CPU speed** — single-core workloads should hit **~4.5 GHz** under load. Multi-core workloads should sustain **~3.0 GHz** at 32-45W.

If you see the chip stuck at <2 GHz under load, ThrottleStop didn't apply. Check the **Limits** column at the bottom of the main window — it should show "OK" not "PL1" or "PROCHOT".

### Step 4 — Auto-launch on every boot

This is the part that makes ThrottleStop apply automatically without you clicking it every time. Use the included Task Scheduler XML:

#### Option A — automated via PowerShell (recommended)
1. Right-click `install.ps1` → Run with PowerShell (as admin)
2. When prompted, point it at your ThrottleStop.exe path
3. Done — reboot to verify

#### Option B — manual via Task Scheduler GUI
1. Open Task Scheduler (Win+R → `taskschd.msc`)
2. Action → **Import Task** → select `lpl-unlock.xml` from this directory
3. Edit the imported task: set the path of the program to your `ThrottleStop.exe`
4. Verify the trigger: "On user logon" with **Run with highest privileges** ✓
5. OK

After this, ThrottleStop launches automatically on every login, applies your saved profile, and runs minimized in the system tray.

## Windows-side optimizations (often missed — significant impact)

These don't exist in ThrottleStop but matter for benchmark numbers and real-world perf:

### 1. Windows Power Plan — must be Ultimate Performance

```powershell
# Run as admin
powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61    # creates Ultimate Performance plan
powercfg /list                                                      # find its GUID
powercfg /setactive <GUID-from-above>
```

If `Ultimate Performance` doesn't exist on your edition, use `High performance`:
```powershell
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

### 2. Lenovo Vantage — set to highest tier (but it's NOT enough on its own)

**Important: Vantage's "Performance Mode" still caps PL1 at ~20W** on V/IdeaPad/ThinkBook lines — that's less than half the chip's rated TDP. Vantage is not the unlock; it just makes the EC throttle "merely bad" instead of "catastrophic." **The real unlock is ThrottleStop's MMIO Lock above.**

That said, Vantage continually re-asserts EC settings, so:
- Set Vantage to its highest tier (**Performance Mode** or "Extreme Performance" if available) — at least Vantage won't fight your ThrottleStop unlock
- Make sure Vantage starts with Windows (Task Manager → Startup)
- If Vantage is set to "Battery Saver" or "Intelligent Cooling," it WILL fight ThrottleStop at runtime and bring you back to the lower cap

### 3. Disable Windows Defender during benchmarks (optional)

During Geekbench / Cinebench runs, real-time scanning eats 5-15% CPU. Add exclusions:
- Add `C:\Program Files\ThrottleStop\` to Defender exclusions
- Add Geekbench / Cinebench install dir to exclusions
- Or temporarily disable real-time protection only while benchmarking

### 4. Close background processes before sustained workloads

OneDrive, Edge prefetcher, Teams, Discord, Steam, Slack — close them before any compile/build/benchmark. Each eats ~1-3% CPU which compounds on a 12-thread chip.

### 5. Verify your charger

Lenovo OEM 65W barrel jack works correctly. Third-party USB-C chargers (even rated 65W+) can cause the EC to throttle even harder regardless of ThrottleStop. **Use the original Lenovo brick.**

## Profile recommendations for V17 G4 (i5-13420H)

| Profile | PL1 | PL2 | Use case |
|---|---|---|---|
| **Daily** | 36 W | 58 W | Recommended — strong perf, low fan noise, ~80°C peak |
| **Performance** | 45 W | 65 W | Heavy multi-thread, fan audible, ~85-90°C |
| **Burst** | 60 W | 90 W | Benchmarks / brief intense tasks; pulls from battery during bursts |
| **Idle / Battery** | 8 W | 8 W | Maximum battery life on the road |

Other Lenovo IdeaPad / V / ThinkBook models will need different values — see [`data/known-good.yml`](../data/known-good.yml) for community contributions.

## Troubleshooting

**Q: ThrottleStop says "Locked" next to PL1 — is that bad?**
A: No, that's GOOD. It means our MMIO lock is engaged and the EC can no longer reset PL1.

**Q: After reboot, ThrottleStop didn't auto-launch.**
A: Check Task Scheduler → your task → History tab. Common cause: User Account Control (UAC) blocking. The task must be set to "Run with highest privileges" AND "Run only when user is logged on" with your account.

**Q: My Cinebench score is still low after applying ThrottleStop.**
A: Check Limits column at bottom of ThrottleStop. If it shows "PROCHOT" → step 1 BD PROCHOT didn't unstick. If it shows "PL1" → your PL1 setting is below where the chip wants to draw — increase it. If "OK" → look at Windows-side issues (Power Plan, Vantage tier, Defender, background apps).

**Q: Can I damage my laptop?**
A: No. The CPU has its own thermal protection (100°C trip) which still works. If you set PL1 too high, the chip will hit its trip and shut down cleanly. The only thing this tool changes is the EC-imposed firmware cap that throttles BELOW the chip's safe limits.

## Comparison with the Linux side

| Feature | Linux (`lpl`) | Windows (ThrottleStop) |
|---|---|---|
| MMIO Lock for PL1/PL2 | ✓ via `setPL.sh` | ✓ via TPL window |
| Auto-apply on boot | ✓ systemd | ✓ Task Scheduler |
| Live wattage tray indicator | ✓ `lpl-monitor` | ✓ ThrottleStop tray icon |
| Profile switching | ✓ `lpl <profile>` or tray menu | ✓ ThrottleStop profile slots |
| Battery conservation toggle | ✓ via tray | Use Lenovo Vantage |
| Auto-tune for chassis | ✓ `lpl autotune` (planned) | Manual via TPL |

Linux numbers tend to be slightly higher than Windows for the same PL1 setting because Linux runs leaner at idle (no Defender scanning, fewer background processes, no Vantage daemon), leaving more of your power budget for actual work.
