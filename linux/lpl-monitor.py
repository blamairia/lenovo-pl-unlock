#!/usr/bin/python3
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AyatanaAppIndicator3', '0.1')
from gi.repository import Gtk, AyatanaAppIndicator3 as AppIndicator3, GLib
import subprocess
import glob

RAPL_PATH = "/sys/class/powercap/intel-rapl:0/energy_uj"
RAPL_MAX_PATH = "/sys/class/powercap/intel-rapl:0/max_energy_range_uj"
PL1_PATH = "/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"
CONSERVATION_PATH = "/sys/devices/pci0000:00/0000:00:1f.0/PNP0C09:00/VPC2004:00/conservation_mode"
CONSERVATION_HELPER = "/usr/local/bin/lenovo-conservation"
LPL_HELPER = "/usr/local/bin/lpl-set-profile"
INTERVAL_SEC = 2
PROFILES = ["performance", "balanced", "power-saver"]
# (name, PL1 watts, label)
LPL_PROFILES = [
    ("eco",         12, "Eco (12W) — battery saver, max hours"),
    ("balanced",    22, "Balanced (22W) — quiet all-day"),
    ("daily",       36, "Daily (36W) — recommended"),
    ("performance", 45, "Performance (45W) — heavy load"),
    ("burst",       60, "Burst (60W/90W) — short bursts only"),
]

# Battery + power supply paths (Lenovo V17 G4)
BAT_BASE = "/sys/class/power_supply/BAT0"
AC_BASE = "/sys/class/power_supply/ADP0"
SYSTEM_OVERHEAD_W = 8  # rough estimate: screen + RAM + SSD + wifi + chipset

def read_int(path):
    with open(path) as f:
        return int(f.read().strip())

def read_str(path):
    with open(path) as f:
        return f.read().strip()

def read_conservation():
    try:
        return read_int(CONSERVATION_PATH) == 1
    except Exception:
        return None

def write_conservation(enabled):
    arg = "1" if enabled else "0"
    r = subprocess.run(["sudo", "-n", CONSERVATION_HELPER, arg],
                       capture_output=True, text=True, timeout=5)
    return r.returncode == 0

def read_profile():
    try:
        r = subprocess.run(["powerprofilesctl", "get"], capture_output=True, text=True, timeout=2)
        return r.stdout.strip()
    except Exception:
        return None

def set_profile(name):
    subprocess.run(["powerprofilesctl", "set", name], timeout=3)

def read_lpl_pl1_w():
    try:
        return read_int(PL1_PATH) // 1_000_000
    except Exception:
        return None

def detect_lpl_profile():
    pl1 = read_lpl_pl1_w()
    if pl1 is None:
        return None
    best = None
    best_diff = 999
    for name, w, _ in LPL_PROFILES:
        d = abs(pl1 - w)
        if d < best_diff:
            best, best_diff = name, d
    return best if best_diff <= 3 else None

def battery_info(live_pkg_w):
    """Return (label_str, sensitive) describing current battery state.
    Uses live_pkg_w to estimate hours when on AC.
    """
    try:
        cap = read_int(f"{BAT_BASE}/capacity")
        status = read_str(f"{BAT_BASE}/status")
        e_now_wh = read_int(f"{BAT_BASE}/energy_now") / 1e6
        e_full_wh = read_int(f"{BAT_BASE}/energy_full") / 1e6
        e_design_wh = read_int(f"{BAT_BASE}/energy_full_design") / 1e6
        cycles = 0
        try:
            cycles = read_int(f"{BAT_BASE}/cycle_count")
        except Exception:
            pass
        ac_online = 0
        try:
            ac_online = read_int(f"{AC_BASE}/online")
        except Exception:
            pass
        # Actual discharge rate (only meaningful when on battery)
        p_now_w = 0.0
        try:
            p_now_w = read_int(f"{BAT_BASE}/power_now") / 1e6
        except Exception:
            pass

        health_pct = 100 * e_full_wh / e_design_wh if e_design_wh > 0 else 100
        total_w = max(0.5, live_pkg_w + SYSTEM_OVERHEAD_W)

        if status == "Discharging":
            # Actually on battery — use measured power_now if available
            draw = p_now_w if p_now_w > 1 else total_w
            hours = e_now_wh / draw
            return (f"🔋 {cap}% · {hours:.1f}h left ({draw:.1f}W draw)", True)
        elif status == "Charging":
            return (f"🔌 {cap}% · charging", True)
        elif status in ("Not charging", "Full"):
            # AC connected, battery either full or capped (conservation mode)
            hours_full = e_full_wh / total_w
            hours_now = e_now_wh / total_w
            return (f"🔌 {cap}% · ~{hours_now:.1f}h if unplug · {hours_full:.1f}h from full", True)
        else:
            return (f"🔋 {cap}% · {status}", False)
    except Exception as ex:
        return (f"Battery: {ex}", False)

def battery_health_str():
    try:
        e_full = read_int(f"{BAT_BASE}/energy_full") / 1e6
        e_design = read_int(f"{BAT_BASE}/energy_full_design") / 1e6
        cycles = 0
        try:
            cycles = read_int(f"{BAT_BASE}/cycle_count")
        except Exception:
            pass
        pct = 100 * e_full / e_design if e_design > 0 else 100
        return f"Battery health: {pct:.0f}% · {e_full:.1f}/{e_design:.0f}Wh · {cycles} cycles"
    except Exception:
        return "Battery health: unknown"

def set_lpl_profile(name):
    r = subprocess.run(["sudo", "-n", LPL_HELPER, name],
                       capture_output=True, text=True, timeout=10)
    return r.returncode == 0

def avg_freq_ghz():
    files = glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")
    if not files:
        return None
    total = 0
    for f in files:
        try:
            total += read_int(f)
        except Exception:
            pass
    return total / len(files) / 1e6

def max_freq_ghz():
    files = glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")
    if not files:
        return 0
    return max(read_int(f) for f in files) / 1e6

def cpu_busy_pct(prev):
    with open("/proc/stat") as f:
        parts = f.readline().split()[1:]
    nums = [int(x) for x in parts[:8]]
    user, nice, sys_, idle, iowait, irq, softirq, steal = nums
    busy = user + nice + sys_ + irq + softirq + steal
    total = busy + idle + iowait
    if prev is None:
        return None, (busy, total)
    db = busy - prev[0]
    dt = total - prev[1]
    if dt <= 0:
        return None, (busy, total)
    return 100.0 * db / dt, (busy, total)

def safe_read_int(path, default=0):
    """Read a sysfs int file, return default on permission/IO error.
    Used so the tray can start even when energy_uj isn't yet world-readable
    (race with cpu-perf-tweaks.service at boot)."""
    try:
        return read_int(path)
    except (PermissionError, FileNotFoundError, OSError, ValueError):
        return default

class WattageTray:
    def __init__(self):
        # Tolerate the boot race: energy_uj may not be world-readable yet.
        # The tick() loop will retry every 2 sec and the chmod typically
        # lands within ~30 sec of session start.
        self.last_energy = safe_read_int(RAPL_PATH, default=0)
        self.last_time = GLib.get_monotonic_time()
        self.energy_max = safe_read_int(RAPL_MAX_PATH, default=2**63)
        self.energy_readable = self.last_energy > 0
        self.cpu_prev = None

        self.indicator = AppIndicator3.Indicator.new(
            "cpu-wattage",
            "power-profile-performance-symbolic",
            AppIndicator3.IndicatorCategory.HARDWARE,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_label("⚡ …", "⚡ 99.9W")
        self.indicator.set_title("CPU Power Monitor")

        self.menu = Gtk.Menu()

        self.power_label = Gtk.MenuItem(label="Reading…")
        self.power_label.set_sensitive(False)
        self.menu.append(self.power_label)

        self.freq_label = Gtk.MenuItem(label="Freq: …")
        self.freq_label.set_sensitive(False)
        self.menu.append(self.freq_label)

        self.cpu_label = Gtk.MenuItem(label="CPU: …")
        self.cpu_label.set_sensitive(False)
        self.menu.append(self.cpu_label)

        self.battery_label = Gtk.MenuItem(label="Battery: …")
        self.battery_label.set_sensitive(False)
        self.menu.append(self.battery_label)

        self.bat_health_label = Gtk.MenuItem(label=battery_health_str())
        self.bat_health_label.set_sensitive(False)
        self.menu.append(self.bat_health_label)

        self.menu.append(Gtk.SeparatorMenuItem())

        header_profile = Gtk.MenuItem(label="Power Profile:")
        header_profile.set_sensitive(False)
        self.menu.append(header_profile)

        self.profile_items = {}
        current = read_profile()
        first_radio = None
        for prof in PROFILES:
            item = Gtk.RadioMenuItem.new_with_label_from_widget(first_radio, f"  {prof}")
            if first_radio is None:
                first_radio = item
            if prof == current:
                item.set_active(True)
            handler = item.connect("toggled", self.on_profile_toggled, prof)
            self.profile_items[prof] = (item, handler)
            self.menu.append(item)

        self.menu.append(Gtk.SeparatorMenuItem())

        header_lpl = Gtk.MenuItem(label="LPL Mode (Lenovo PL Unlock):")
        header_lpl.set_sensitive(False)
        self.menu.append(header_lpl)

        self.lpl_items = {}
        current_lpl = detect_lpl_profile()
        first_lpl_radio = None
        for name, w, label in LPL_PROFILES:
            item = Gtk.RadioMenuItem.new_with_label_from_widget(first_lpl_radio, f"  {label}")
            if first_lpl_radio is None:
                first_lpl_radio = item
            if name == current_lpl:
                item.set_active(True)
            handler = item.connect("toggled", self.on_lpl_toggled, name)
            self.lpl_items[name] = (item, handler)
            self.menu.append(item)

        self.menu.append(Gtk.SeparatorMenuItem())

        self.conservation_item = Gtk.CheckMenuItem(label="Limit battery charge to 60% (Conservation Mode)")
        state = read_conservation()
        if state is None:
            self.conservation_item.set_label("Conservation mode (unavailable)")
            self.conservation_item.set_sensitive(False)
        else:
            self.conservation_item.set_active(state)
        self._cons_handler = self.conservation_item.connect("toggled", self.on_conservation_toggled)
        self.menu.append(self.conservation_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        refresh_item = Gtk.MenuItem(label="Refresh state")
        refresh_item.connect("activate", lambda _: self.refresh_all())
        self.menu.append(refresh_item)

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda _: Gtk.main_quit())
        self.menu.append(quit_item)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        GLib.timeout_add_seconds(INTERVAL_SEC, self.tick)

    def tick(self):
        try:
            # If energy_uj wasn't readable at boot (perms race),
            # try again every tick — chmod usually lands within ~30s.
            if not self.energy_readable:
                e = safe_read_int(RAPL_PATH, default=0)
                if e > 0:
                    self.energy_readable = True
                    self.last_energy = e
                    self.last_time = GLib.get_monotonic_time()
                    self.energy_max = safe_read_int(RAPL_MAX_PATH, default=2**63)
                    self.indicator.set_label("⚡ …", "⚡ 99.9W")
                else:
                    # Still unreadable. Keep showing placeholder, don't crash.
                    self.indicator.set_label("⚡ —", "⚡ 99.9W")
                    self.power_label.set_label("Power: waiting for /sys perms…")
                    return True

            e = safe_read_int(RAPL_PATH, default=self.last_energy)
            t = GLib.get_monotonic_time()
            dt = (t - self.last_time) / 1e6
            de = e - self.last_energy
            if de < 0:
                de += self.energy_max
            watts = de / 1e6 / dt if dt > 0 else 0
            self.last_energy = e
            self.last_time = t

            avg_f = avg_freq_ghz() or 0
            max_f = max_freq_ghz()
            busy, self.cpu_prev = cpu_busy_pct(self.cpu_prev)
            busy_str = f"{busy:.0f}%" if busy is not None else "…"

            self.indicator.set_label(f"⚡ {watts:.1f}W  {busy_str}", "⚡ 99.9W  100%")
            self.power_label.set_label(f"Power: {watts:.2f} W")
            self.freq_label.set_label(f"Freq: avg {avg_f:.2f} GHz  max {max_f:.2f} GHz")
            self.cpu_label.set_label(f"CPU busy: {busy_str}")
            bat_str, _ = battery_info(watts)
            self.battery_label.set_label(bat_str)
        except Exception as ex:
            self.power_label.set_label(f"Error: {ex}")
        return True

    def on_conservation_toggled(self, item):
        desired = item.get_active()
        ok = write_conservation(desired)
        if not ok:
            actual = read_conservation()
            item.handler_block(self._cons_handler)
            item.set_active(bool(actual))
            item.handler_unblock(self._cons_handler)

    def on_profile_toggled(self, item, profile):
        if not item.get_active():
            return
        try:
            set_profile(profile)
        except Exception:
            pass
        GLib.timeout_add(500, self.refresh_profile)

    def refresh_profile(self):
        current = read_profile()
        if not current:
            return False
        for prof, (item, handler) in self.profile_items.items():
            item.handler_block(handler)
            item.set_active(prof == current)
            item.handler_unblock(handler)
        return False

    def on_lpl_toggled(self, item, name):
        if not item.get_active():
            return
        ok = set_lpl_profile(name)
        # Re-detect after a short delay (setPL takes a sec to apply)
        GLib.timeout_add(800, self.refresh_lpl)
        if not ok:
            self.power_label.set_label(f"LPL switch failed for: {name}")

    def refresh_lpl(self):
        current = detect_lpl_profile()
        if not current:
            return False
        for name, (item, handler) in self.lpl_items.items():
            item.handler_block(handler)
            item.set_active(name == current)
            item.handler_unblock(handler)
        return False

    def refresh_all(self):
        self.refresh_profile()
        self.refresh_lpl()
        state = read_conservation()
        if state is not None:
            self.conservation_item.handler_block(self._cons_handler)
            self.conservation_item.set_active(state)
            self.conservation_item.handler_unblock(self._cons_handler)

if __name__ == "__main__":
    WattageTray()
    Gtk.main()
