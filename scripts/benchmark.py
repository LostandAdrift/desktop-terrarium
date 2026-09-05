#!/usr/bin/env python3
"""Opt-in native resource benchmark; leave the desktop undisturbed while running.

Measures the selected Omarchy shell and, in one live phase, its single owned
observer. Invalid UI phases or changed process identities produce no resource
numbers. Only aggregate counters and fixed diagnostics are printed.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

PLUGIN = "io.github.lostandadrift.terrarium"
HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
POLL = .5
PHASES = {
    "closed": {"opened": False, "animationRunning": False, "collectorRunning": False},
    "animatedDemo": {"opened": True, "demo": True, "section": "garden", "reducedMotion": False, "animationRunning": True, "collectorRunning": False},
    "stillDemo": {"opened": True, "demo": True, "section": "garden", "reducedMotion": True, "animationRunning": False, "collectorRunning": False},
    "options": {"opened": True, "demo": True, "section": "options", "reducedMotion": False, "animationRunning": False, "collectorRunning": False},
    "art": {"opened": True, "demo": True, "section": "art", "reducedMotion": False, "animationRunning": True, "collectorRunning": False},
    "liveStillObserverBaseline": {"opened": True, "demo": False, "section": "garden", "reducedMotion": True, "animationRunning": False, "collectorRunning": True},
}


class BenchmarkError(Exception):
    """Fixed diagnostic code; never include raw state, paths, or child output."""


def command(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, check=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        raise BenchmarkError("native_command_failed") from None


def parse_counter(text):
    fields = text.rsplit(")", 1)[1].split()
    return {"starttime": int(fields[19]), "ticks": int(fields[11]) + int(fields[12]),
            "rss": max(0, int(fields[21])) * PAGE, "parent": int(fields[1])}


def counter(pid):
    try:
        return parse_counter(Path(f"/proc/{pid}/stat").read_text())
    except (OSError, ValueError, IndexError):
        raise BenchmarkError("process_counter_unavailable") from None


def check_identity(before, after):
    if before["starttime"] != after["starttime"]:
        raise BenchmarkError("process_identity_changed")
    if after["ticks"] < before["ticks"]:
        raise BenchmarkError("process_counter_regressed")


def select_shell(instances, config):
    if not isinstance(instances, list) or len(instances) != 1:
        raise BenchmarkError("shell_instance_missing_or_ambiguous")
    item = instances[0]
    if not isinstance(item, dict) or type(item.get("pid")) is not int or item["pid"] <= 1:
        raise BenchmarkError("shell_instance_invalid")
    if item.get("config_path") != str(config):
        raise BenchmarkError("shell_config_mismatch")
    return item["pid"]


class Native:
    def __init__(self):
        config = (Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell/shell.qml").resolve()
        try:
            instances = json.loads(command("quickshell", "list", "--json", "--path", str(config), "--newest"))
            self.pid = select_shell(instances, config)
            proc = Path(f"/proc/{self.pid}")
            if proc.stat().st_uid != os.getuid() or (proc / "exe").resolve().name not in ("quickshell", "qs"):
                raise BenchmarkError("shell_owner_or_executable_mismatch")
        except (OSError, ValueError):
            raise BenchmarkError("shell_discovery_failed") from None
        self.identity = counter(self.pid)

    def call(self, *args):
        check_identity(self.identity, counter(self.pid))
        # Pin both control and counters to this exact instance, including cleanup.
        result = command("quickshell", "ipc", "--pid", str(self.pid), "call", "--", *args)
        if result in ("Target not found.", "Function not found."):
            raise BenchmarkError("native_ipc_unavailable")
        return result

    def states(self):
        try:
            values = json.loads(self.call("terrarium", "allStates"))
        except ValueError:
            raise BenchmarkError("native_state_invalid") from None
        if not isinstance(values, list) or not values or not all(isinstance(s, dict) for s in values):
            raise BenchmarkError("native_state_invalid")
        required = {key: bool for key in ("opened", "demo", "reducedMotion", "animationRunning", "collectorRunning",
                                         "locked", "ambient", "ambientVisible", "exportBusy", "clockRunning", "stale")}
        required.update(screenName=str, section=str, collectorPid=int, watcherCount=int, residents=int, liveSamples=int)
        if any(type(value.get(key)) is not kind for value in values for key, kind in required.items()):
            raise BenchmarkError("native_state_invalid")
        if any(value["section"] not in ("garden", "journal", "guide", "options", "art", "postcard") for value in values):
            raise BenchmarkError("native_state_invalid")
        return values


def selected(states):
    opened = [s for s in states if s.get("opened") is True]
    if len(opened) != 1:
        raise BenchmarkError("panel_not_uniquely_open")
    return opened[0]


def validate_phase(states, phase, screen=None, observer_pid=None, closed_state=None):
    expected = PHASES[phase]
    if any(s.get("locked") is not False or s.get("ambient") is not False or s.get("ambientVisible") is not False for s in states):
        raise BenchmarkError("phase_locked_or_ambient")
    if any(s.get("exportBusy") is not False for s in states):
        raise BenchmarkError("phase_export_active")
    if phase == "closed":
        if any(s.get("opened") is not False or s.get("animationRunning") is not False or s.get("clockRunning") is not False for s in states):
            raise BenchmarkError("closed_phase_active")
        if closed_state is not None and [(s.get("screenName"), s.get("demo"), s.get("section"), s.get("reducedMotion")) for s in states] != closed_state:
            raise BenchmarkError("closed_settings_changed")
        current = states[0]
    else:
        current = selected(states)
        if current.get("screenName") != screen:
            raise BenchmarkError("panel_instance_changed")
        if any(current.get(key) != value for key, value in expected.items()):
            raise BenchmarkError("phase_state_changed")
        if current.get("clockRunning") is not True:
            raise BenchmarkError("phase_clock_stopped")
        if any(s is not current and (s.get("animationRunning") is not False or s.get("clockRunning") is not False) for s in states):
            raise BenchmarkError("other_panel_active")
        if expected["demo"] and current.get("residents", 0) <= 0:
            raise BenchmarkError("demo_not_ready")
    observing = expected["collectorRunning"]
    for value in states:
        if value.get("collectorRunning") is not observing or value.get("watcherCount") != int(observing):
            raise BenchmarkError("observer_lifetime_changed")
        pid = value.get("collectorPid")
        if observing and (type(pid) is not int or pid <= 1 or (observer_pid is not None and pid != observer_pid)):
            raise BenchmarkError("observer_identity_changed")
        if not observing and pid != 0:
            raise BenchmarkError("unexpected_observer")
    if observing and (current.get("stale") is not False or current.get("liveSamples", 0) < 2):
        raise BenchmarkError("observer_not_ready")
    return current


def await_phase(native, phase, screen=None, timeout=12):
    deadline = time.monotonic() + timeout
    last_reason = "phase_did_not_settle"
    while time.monotonic() < deadline:
        states = native.states()
        try:
            validate_phase(states, phase, screen)
            return states
        except BenchmarkError as error:
            last_reason = str(error)
        time.sleep(.15)
    raise BenchmarkError(last_reason)


def measure(native, phase, seconds, screen=None):
    result = {"valid": False, "requestedSeconds": seconds, "expected": PHASES[phase], "stateChecks": 0}
    started = time.monotonic()
    try:
        states = await_phase(native, phase, screen)
        current = validate_phase(states, phase, screen)
        closed_state = [(s.get("screenName"), s.get("demo"), s.get("section"), s.get("reducedMotion")) for s in states] if phase == "closed" else None
        pids = {"omarchyShell": native.pid}
        observer_pid = current["collectorPid"] if PHASES[phase]["collectorRunning"] else None
        if observer_pid:
            pids["ownedObserver"] = observer_pid
        before = {role: counter(pid) for role, pid in pids.items()}
        check_identity(native.identity, before["omarchyShell"])
        if observer_pid and before["ownedObserver"]["parent"] != native.pid:
            raise BenchmarkError("observer_not_owned_by_shell")
        peak = {role: value["rss"] for role, value in before.items()}
        first_samples = current.get("liveSamples", 0)
        residents = [current.get("residents", 0)]
        result["settleSeconds"] = round(time.monotonic() - started, 3)
        started = time.monotonic()
        while True:
            current = validate_phase(native.states(), phase, screen, observer_pid, closed_state)
            result["stateChecks"] += 1
            residents.append(current.get("residents", 0))
            after = {role: counter(pid) for role, pid in pids.items()}
            for role, value in after.items():
                check_identity(before[role], value)
                peak[role] = max(peak[role], value["rss"])
            elapsed = time.monotonic() - started
            if elapsed >= seconds:
                break
            time.sleep(min(POLL, seconds - elapsed))
        if observer_pid and current.get("liveSamples", 0) <= first_samples:
            raise BenchmarkError("observer_samples_did_not_advance")
        result.update(valid=True, measuredSeconds=round(elapsed, 3),
                      residentCountRange={"min": min(residents), "max": max(residents)}, processes={
            role: {"pid": pid, "starttimeTicks": before[role]["starttime"],
                   "cpuPercentOfOneCore": round(100 * (after[role]["ticks"] - before[role]["ticks"]) / HZ / elapsed, 2),
                   "rssMiB": round(after[role]["rss"] / 1048576, 2), "sampledPeakRssMiB": round(peak[role] / 1048576, 2)}
            for role, pid in pids.items()})
    except BenchmarkError as error:
        result.update(reason=str(error), elapsedSeconds=round(time.monotonic() - started, 3))
    return result


def set_flag(native, key, command_name, wanted):
    if selected(native.states()).get(key) != wanted:
        native.call("terrarium", command_name)


def restore(native, original, changed):
    if changed is not None:
        native.call("shell", "summon", PLUGIN, "{}")
        if selected(native.states()).get("screenName") != changed.get("screenName"):
            raise BenchmarkError("restore_panel_instance_changed")
        set_flag(native, "demo", "demo", changed["demo"])
        native.call("terrarium", "section", changed["section"])
    states = native.states()
    for key, action in (("reducedMotion", "motion"), ("ambient", "ambient")):
        if states[0].get(key) != original[0][key]:
            native.call("terrarium", action)
    if not any(s["opened"] for s in original):
        native.call("shell", "hide", PLUGIN)
    else:
        native.call("shell", "summon", PLUGIN, "{}")
    deadline = time.monotonic() + 5
    fields = ("screenName", "opened", "demo", "section", "reducedMotion", "ambient")
    wanted = sorted(tuple(s.get(k) for k in fields) for s in original)
    while time.monotonic() < deadline:
        if sorted(tuple(s.get(k) for k in fields) for s in native.states()) == wanted:
            return
        time.sleep(.15)
    raise BenchmarkError("original_state_not_restored")


def run(seconds):
    native = Native()
    original = native.states()
    if any(s.get("locked") or s.get("exportBusy") or s.get("section") == "postcard" for s in original):
        raise BenchmarkError("finish_postcard_or_unlock_before_benchmark")
    if sum(s.get("opened") is True for s in original) > 1:
        raise BenchmarkError("multiple_panels_open")
    report = {"valid": False, "logicalCpus": os.cpu_count(), "secondsPerPhase": seconds,
              "sampleIntervalSeconds": POLL, "phases": {}, "restored": False,
              "unmeasured": {"postcard": "Keyboard focus ownership is not provable through the native state API."},
              "caveats": ["Shell counters include every Omarchy shell component and the cost of benchmark IPC polls.",
                          "Demo phases use synthetic residents; the observer baseline uses current local workload without retaining names or raw samples.",
                          "CPU is percent of one core; RSS peaks are sampled, not allocation peaks. No GPU or power cost is measured.",
                          "Other desktop activity and compositor work can change results. Phases run sequentially, not as isolated or causal comparisons.",
                          "State is checked at each poll; transitions shorter than the polling interval can be missed."]}
    changed = None
    try:
        if original[0]["ambient"]:
            native.call("terrarium", "ambient")
        native.call("shell", "hide", PLUGIN)
        for phase in PHASES:
            if phase != "closed":
                if changed is None:
                    native.call("shell", "summon", PLUGIN, "{}")
                    target = selected(native.states())
                    changed = next((s for s in original if s.get("screenName") == target.get("screenName")), None)
                    if changed is None:
                        raise BenchmarkError("panel_instance_changed")
                else:
                    target = selected(native.states())
                    if target.get("screenName") != changed.get("screenName"):
                        raise BenchmarkError("panel_instance_changed")
                expected = PHASES[phase]
                set_flag(native, "demo", "demo", expected["demo"])
                set_flag(native, "reducedMotion", "motion", expected["reducedMotion"])
                native.call("terrarium", "section", expected["section"])
            result = measure(native, phase, seconds, changed.get("screenName") if changed else None)
            report["phases"][phase] = result
            if not result["valid"]:
                break
    except BenchmarkError as error:
        report["reason"] = str(error)
    except KeyboardInterrupt:
        report["reason"] = "interrupted"
    finally:
        try:
            restore(native, original, changed)
            report["restored"] = True
        except BenchmarkError as error:
            report["restorationReason"] = str(error)
    for phase in PHASES:
        report["phases"].setdefault(phase, {"valid": False, "reason": "not_run_after_invalid_phase"})
    report["valid"] = report["restored"] and all(p["valid"] for p in report["phases"].values())
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=15)
    args = parser.parse_args()
    if not 5 <= args.seconds <= 60:
        parser.error("--seconds must be between 5 and 60")
    try:
        result = run(args.seconds)
    except BenchmarkError as error:
        result = {"valid": False, "reason": str(error)}
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["valid"] else 1)
