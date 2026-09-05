#!/usr/bin/env python3
"""Opt-in offscreen soak of the synthetic view and one owned live observer.

Example: python3 scripts/soak.py --seconds 1800 --output /tmp/terrarium-soak.json
Only aggregate resource measurements and invariants are retained. No native
desktop surface, process names, raw telemetry, or screenshots are saved.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import json
import math
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
PHASES = {"warmup", "animated", "paused", "hidden", "reduced", "journal", "options", "art", "postcard", "teardown"}
QUIET_PHASES = {"paused", "hidden", "reduced", "journal", "options", "postcard", "teardown"}
POSTCARD_COUNTS = ("postcardRequests", "postcardReadyCount", "postcardReleases", "postcardFrozenChecks", "postcardLiveUpdates")
HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")


class SoakError(Exception):
    """A fixed diagnostic code, never child output or raw telemetry."""


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def parse_counter(data):
    fields = data.rsplit(")", 1)[1].split()
    return {"start": int(fields[19]), "ticks": int(fields[11]) + int(fields[12]),
            "rss": max(0, int(fields[21])) * PAGE}


def counter(pid):
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
            return parse_counter(handle.read(8192))
    except FileNotFoundError:
        return None
    except (OSError, ValueError, IndexError):
        raise SoakError("owned_process_counter_unreadable") from None


@dataclass
class WindowStats:
    count: int = 0
    first: float = 0
    last: float = 0
    low: float = math.inf
    high: float = 0
    total: float = 0
    sum_x: float = 0
    sum_xx: float = 0
    sum_xy: float = 0

    def add(self, elapsed, value):
        if not self.count:
            self.first = value
        self.count += 1
        self.last = value
        self.low = min(self.low, value)
        self.high = max(self.high, value)
        self.total += value
        self.sum_x += elapsed
        self.sum_xx += elapsed * elapsed
        self.sum_xy += elapsed * value

    def result(self):
        if not self.count:
            return {"samples": 0}
        denominator = self.count * self.sum_xx - self.sum_x * self.sum_x
        slope = ((self.count * self.sum_xy - self.sum_x * self.total) / denominator) if denominator > 0 else None
        return {"samples": self.count, "first": round(self.first, 4), "last": round(self.last, 4),
                "mean": round(self.total / self.count, 4), "min": round(self.low, 4), "max": round(self.high, 4),
                "trendPerMinute": round(slope * 60, 4) if slope is not None else None}


@dataclass
class OwnedChild:
    role: str
    process: subprocess.Popen
    starttime: int
    previous: dict
    measured_at: float
    rss: dict = field(default_factory=dict)
    cpu: dict = field(default_factory=dict)
    stopped: bool = False

    def sample(self, elapsed, phase, bucket):
        current = counter(self.process.pid)
        if current is None:
            return
        if current["start"] != self.starttime:
            raise SoakError(self.role + "_identity_changed")
        now = time.monotonic()
        interval = now - self.measured_at
        ticks = current["ticks"] - self.previous["ticks"]
        if ticks < 0:
            raise SoakError(self.role + "_counter_reset")
        for key in {"all", "phase:" + phase, bucket}:
            self.rss.setdefault(key, WindowStats()).add(elapsed, current["rss"] / 1048576)
            if interval > 0:
                self.cpu.setdefault(key, WindowStats()).add(elapsed, ticks * 100 / HZ / interval)
        self.previous, self.measured_at = current, now

    def result(self):
        steady = sorted(k for k in self.rss if k.startswith("steady:"))
        trend = None
        if len(steady) > 1:
            first, last = self.rss[steady[0]], self.rss[steady[-1]]
            trend = round(last.total / last.count - first.total / first.count, 4)
        return {"pid": self.process.pid, "starttimeTicks": self.starttime, "exitCode": self.process.poll(),
                "stoppedAndReaped": self.stopped, "rssMiB": {k: v.result() for k, v in sorted(self.rss.items())},
                "cpuPercentOfOneCore": {k: v.result() for k, v in sorted(self.cpu.items())},
                "lastMinusFirstSteadyMeanRssMiB": trend}


def launch(role, command, env):
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    try:
        identity = counter(process.pid)
        if identity is None:
            raise SoakError(role + "_exited_during_start")
        return OwnedChild(role, process, identity["start"], identity, time.monotonic())
    except BaseException:
        # This exact Popen child has not yet been reaped; no PID search is used.
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        for handle in (process.stdin, process.stdout, process.stderr):
            handle.close()
        raise


def stop(child, errors):
    process = child.process
    try:
        if process.poll() is None:
            try:
                identity = counter(process.pid)
            except SoakError:
                errors.append(child.role + "_cleanup_counter_unreadable")
                # This Popen child is still unreaped, so its PID cannot have
                # been reused. A counter read error must not leak our child.
                identity = None
            if identity and identity["start"] != child.starttime:
                errors.append(child.role + "_cleanup_identity_changed")
                return
            if child.role == "observer":
                process.stdin.close()
            else:
                process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    identity = counter(process.pid)
                except SoakError:
                    errors.append(child.role + "_cleanup_counter_unreadable")
                    identity = None
                if identity and identity["start"] != child.starttime:
                    errors.append(child.role + "_cleanup_identity_changed")
                    return
                errors.append(child.role + "_forced_stop")
                process.kill()
                process.wait(timeout=3)
        remaining = counter(process.pid)
        child.stopped = process.poll() is not None and (remaining is None or remaining["start"] != child.starttime)
        if not child.stopped:
            errors.append(child.role + "_cleanup_failed")
        if child.role == "observer" and process.poll() not in (None, 0):
            errors.append("observer_stop_exit_error")
    except (OSError, subprocess.TimeoutExpired, SoakError):
        errors.append(child.role + "_cleanup_failed")
    finally:
        for handle in (process.stdin, process.stdout, process.stderr):
            if not handle.closed:
                handle.close()


def validate_observation(line):
    try:
        sample = json.loads(line)
        if not isinstance(sample, dict) or type(sample.get("version")) is not int or sample["version"] != 1:
            raise ValueError()
        for key in ("timestamp", "interval", "processCount", "uptimeSeconds"):
            if not finite(sample[key]) or sample[key] < 0:
                raise ValueError()
        if sample["cpu"] is not None and (not finite(sample["cpu"]) or not 0 <= sample["cpu"] <= 100):
            raise ValueError()
        memory = sample["memory"]
        if any(not finite(memory[k]) or memory[k] < 0 for k in ("usedBytes", "totalBytes")):
            raise ValueError()
        if memory["usedBytes"] > memory["totalBytes"]:
            raise ValueError()
        if memory["percent"] is not None and (not finite(memory["percent"]) or not 0 <= memory["percent"] <= 100):
            raise ValueError()
        network = sample["network"]
        if any(network[k] is not None and (not finite(network[k]) or network[k] < 0) for k in ("rxBytesPerSec", "txBytesPerSec")):
            raise ValueError()
        if not isinstance(network["interfaces"], list) or len(network["interfaces"]) > 64:
            raise ValueError()
        if any(not isinstance(name, str) or len(name) > 64 for name in network["interfaces"]):
            raise ValueError()
        if type(sample["processesAvailable"]) is not bool or not isinstance(sample["processes"], list) or len(sample["processes"]) > 7:
            raise ValueError()
        for group in sample["processes"]:
            if not isinstance(group, dict) or any(not isinstance(group[k], str) or len(group[k]) > 64 for k in ("key", "name")):
                raise ValueError()
            if not finite(group["count"]) or group["count"] < 1 or not finite(group["memoryBytes"]) or group["memoryBytes"] < 0:
                raise ValueError()
            if group["cpu"] is not None and (not finite(group["cpu"]) or group["cpu"] < 0):
                raise ValueError()
            if group["category"] not in {"browser", "editor", "terminal", "agent", "media", "system", "other"}:
                raise ValueError()
        if not isinstance(sample["errors"], list) or len(sample["errors"]) > 8 or any(not isinstance(e, str) or len(e) > 80 for e in sample["errors"]):
            raise ValueError()
        # Only counts leave this function; strings and raw readings are discarded.
        return {"errors": len(sample["errors"]), "processesAvailable": sample["processesAvailable"],
                "processCount": sample["processCount"], "returnedGroups": len(sample["processes"])}
    except (KeyError, TypeError, ValueError, OverflowError, RecursionError):
        raise SoakError("observer_malformed_sample") from None


class Protocol:
    def __init__(self):
        self.metrics = 0
        self.synthetic_samples = 0
        self.valid_samples = 0
        self.unavailable_samples = 0
        self.observer_errors = 0
        self.qml_diagnostics = 0
        self.last_metric = -1
        self.phase = "warmup"
        self.phase_counts = {}
        self.maxima = {k: 0 for k in ("residents", "notes", "scenes", "animatedScenes", "textures", "transients", "paints")}
        self.postcard_counts = {k: 0 for k in POSTCARD_COUNTS}
        self.observer_scale = {k: {"samples": 0, "min": None, "max": 0, "total": 0}
                               for k in ("processCount", "returnedGroups")}
        self.done = False
        self.teardown_seen = False

    def line(self, role, stream, line):
        if role == "observer":
            if stream != "stdout":
                if line.strip():
                    raise SoakError("observer_stderr")
                return
            summary = validate_observation(line)
            self.valid_samples += 1
            self.unavailable_samples += not summary["processesAvailable"]
            self.observer_errors += summary["errors"]
            for key, stats in self.observer_scale.items():
                value = summary[key]
                stats["samples"] += 1
                stats["min"] = value if stats["min"] is None else min(stats["min"], value)
                stats["max"] = max(stats["max"], value)
                stats["total"] += value
            return
        marker = line.find(b"SOAK ")
        if marker < 0:
            if line.strip():
                self.qml_diagnostics += 1
                raise SoakError("view_unexpected_diagnostic")
            return
        try:
            payload = json.loads(line[marker + 5:])
            if not isinstance(payload, dict):
                raise ValueError()
            kind = payload.get("type")
            if kind == "error":
                raise SoakError("view_invariant_failed")
            if kind == "done":
                if payload["viewLoaded"] is not False or not self.teardown_seen:
                    raise ValueError()
                self.done = True
                return
            if kind != "metric" or payload["phase"] not in PHASES:
                raise ValueError()
            second = payload["second"]
            if not finite(second) or second <= self.last_metric:
                raise ValueError()
            if not finite(payload["samples"]) or payload["samples"] < self.synthetic_samples:
                raise ValueError()
            self.synthetic_samples = payload["samples"]
            for key, limit in (("residents", 7), ("notes", 24), ("scenes", 2), ("animatedScenes", 1),
                               ("textures", 14), ("transients", 4), ("paints", 1e9)):
                if type(payload[key]) is not int or not 0 <= payload[key] <= limit:
                    raise ValueError()
                self.maxima[key] = max(self.maxima[key], payload[key])
            phase = payload["phase"]
            if any(type(payload[key]) is not bool for key in ("animationRunning", "viewLoaded", "postcardLoaded", "postcardReady", "postcardAnimated")):
                raise ValueError()
            if payload["animationRunning"] != (payload["animatedScenes"] > 0) or payload["postcardAnimated"]:
                raise ValueError()
            if phase in QUIET_PHASES and payload["animationRunning"]:
                raise ValueError()
            if payload["textures"] > payload["scenes"] * 7 or payload["animatedScenes"] > payload["scenes"]:
                raise ValueError()
            if not payload["viewLoaded"] and (payload["scenes"] or payload["transients"]):
                raise ValueError()
            if payload["viewLoaded"] and payload["scenes"] < 1:
                raise ValueError()
            if phase == "postcard":
                if not payload["postcardLoaded"] or (payload["postcardReady"] and payload["scenes"] != 2):
                    raise ValueError()
            elif payload["postcardLoaded"] or payload["postcardReady"] or payload["scenes"] > 1:
                raise ValueError()
            for key in POSTCARD_COUNTS:
                if type(payload[key]) is not int or not self.postcard_counts[key] <= payload[key] <= 1000000:
                    raise ValueError()
                self.postcard_counts[key] = payload[key]
            if (payload["postcardReadyCount"] > payload["postcardRequests"]
                    or payload["postcardReleases"] > payload["postcardReadyCount"]
                    or payload["postcardFrozenChecks"] < payload["postcardReadyCount"]):
                raise ValueError()
            if phase == "teardown":
                if payload["viewLoaded"]:
                    raise ValueError()
                self.teardown_seen = True
            self.metrics += 1
            self.last_metric, self.phase = second, phase
            self.phase_counts[phase] = self.phase_counts.get(phase, 0) + 1
        except (KeyError, TypeError, ValueError, OverflowError, RecursionError):
            raise SoakError("view_malformed_metric") from None


def run(seconds, qml_binary=None):
    warmup = min(60, max(5, seconds // 10))
    protocol, errors, children = Protocol(), [], []
    started = time.monotonic()
    report = {"schemaVersion": 1, "requestedSeconds": seconds, "warmupSeconds": warmup, "teardownSeconds": 5,
              "renderer": "QtQuick offscreen software", "logicalCpus": os.cpu_count(),
              "limitation": "Resource trends describe the two owned children in this run, not a universal memory bound or native compositor performance. Observer workload is limited to this process's procfs visibility; sandbox/PID namespaces may hide most desktop processes. Aggregate process/group counts expose the observed workload size."}
    with tempfile.TemporaryDirectory(prefix="terrarium-soak-") as runtime_dir, selectors.DefaultSelector() as selector:
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_STYLE_OVERRIDE="Fusion",
                   QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=runtime_dir,
                   QT_LOGGING_RULES="qml.debug=true;qml.info=true;qml.warning=true;qml.critical=true",
                   QT_MESSAGE_PATTERN="%{message}", QT_FORCE_STDERR_LOGGING="1")
        env.pop("DISPLAY", None)
        env.pop("WAYLAND_DISPLAY", None)
        qml = qml_binary or str(Path(os.environ.get("TERRARIUM_QT_BIN", "/usr/lib/qt6/bin")) / "qml")
        buffers = {}
        try:
            children.append(launch("view", [qml, str(ROOT / "tests/Soak.qml"), "--", "--seconds", str(seconds), "--warmup", str(warmup)], env))
            children.append(launch("observer", [sys.executable, "-u", str(ROOT / "scripts/collect.py"), "--interval", "2"], env))
            for child in children:
                for stream in ("stdout", "stderr"):
                    handle = getattr(child.process, stream)
                    os.set_blocking(handle.fileno(), False)
                    selector.register(handle, selectors.EVENT_READ, (child.role, stream))
                    buffers[handle] = bytearray()
            next_measure = time.monotonic()
            last_metric_at = next_measure
            last_observation_at = next_measure
            previous_metric_count = 0
            previous_sample_count = 0
            while True:
                for key, _ in selector.select(timeout=0.25):
                    role, stream = key.data
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        if buffers[key.fileobj]:
                            raise SoakError(role + "_unterminated_output")
                        selector.unregister(key.fileobj)
                        continue
                    buffer = buffers[key.fileobj]
                    buffer.extend(chunk)
                    while b"\n" in buffer:
                        line, _, tail = buffer.partition(b"\n")
                        buffer[:] = tail
                        if len(line) > (131072 if role == "observer" else 4096):
                            raise SoakError(role + "_output_too_large")
                        protocol.line(role, stream, bytes(line))
                    if len(buffer) > (131072 if role == "observer" else 4096):
                        raise SoakError(role + "_output_too_large")
                now = time.monotonic()
                elapsed = now - started
                if protocol.metrics != previous_metric_count:
                    previous_metric_count, last_metric_at = protocol.metrics, now
                if protocol.valid_samples != previous_sample_count:
                    previous_sample_count, last_observation_at = protocol.valid_samples, now
                if now - last_metric_at > 10:
                    raise SoakError("view_heartbeat_timeout")
                if now - last_observation_at > 10:
                    raise SoakError("observer_heartbeat_timeout")
                if now >= next_measure:
                    bucket = "warmup" if elapsed < warmup else "teardown" if protocol.teardown_seen else "steady:%02d" % min(11, int((elapsed - warmup) * 12 / max(1, seconds - warmup - 5)))
                    for child in children:
                        child.sample(elapsed, protocol.phase, bucket)
                    next_measure = now + 1
                for child in children:
                    code = child.process.poll()
                    if code is not None and (child.role != "view" or code != 0 or not protocol.done):
                        raise SoakError(child.role + "_unexpected_exit")
                if protocol.done and children[0].process.poll() is not None:
                    break
                if elapsed > seconds + 15:
                    raise SoakError("run_deadline_exceeded")
            if protocol.valid_samples < max(2, int(seconds / 3)):
                raise SoakError("observer_sample_count_low")
            if set(protocol.phase_counts) != PHASES:
                raise SoakError("phase_coverage_incomplete")
            if protocol.maxima["residents"] != 7 or protocol.maxima["notes"] < 1 or protocol.maxima["transients"] < 1:
                raise SoakError("synthetic_scenario_coverage_incomplete")
            counts = protocol.postcard_counts
            if (not counts["postcardRequests"] or counts["postcardRequests"] != counts["postcardReadyCount"]
                    or counts["postcardRequests"] != counts["postcardReleases"]
                    or counts["postcardFrozenChecks"] < counts["postcardRequests"]
                    or counts["postcardLiveUpdates"] < counts["postcardRequests"]
                    or protocol.maxima["scenes"] != 2 or protocol.maxima["textures"] != 14):
                raise SoakError("postcard_scenario_coverage_incomplete")
        except SoakError as exc:
            errors.append(str(exc))
        except KeyboardInterrupt:
            errors.append("interrupted")
        except (OSError, ValueError, subprocess.SubprocessError):
            errors.append("supervisor_io_error")
        finally:
            for child in reversed(children):
                stop(child, errors)
    report.update({"elapsedSeconds": round(time.monotonic() - started, 3), "passed": not errors, "errors": errors,
                   "viewMetrics": protocol.metrics, "viewSyntheticSamples": protocol.synthetic_samples,
                   "phaseMetricCounts": protocol.phase_counts, "viewMaxima": protocol.maxima,
                   "postcardLifecycleCounts": protocol.postcard_counts,
                   "viewTeardownObserved": protocol.teardown_seen, "qmlDiagnosticLines": protocol.qml_diagnostics,
                   "observerValidSamples": protocol.valid_samples, "observerUnavailableProcessSamples": protocol.unavailable_samples,
                   "observerWorkload": {key: {"samples": stats["samples"], "min": stats["min"], "max": stats["max"],
                        "mean": round(stats["total"] / stats["samples"], 4) if stats["samples"] else None}
                        for key, stats in protocol.observer_scale.items()},
                   "observerErrorCount": protocol.observer_errors, "children": {c.role: c.result() for c in children}})
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=1800, help="total duration, 30–86400 seconds (default 1800)")
    parser.add_argument("--output", type=Path, required=True, help="aggregate JSON report destination")
    args = parser.parse_args(argv)
    if not 30 <= args.seconds <= 86400:
        parser.error("--seconds must be between 30 and 86400")
    if not args.output.parent.is_dir():
        parser.error("--output parent directory must exist")
    report = run(args.seconds)
    temporary = args.output.with_name(args.output.name + ".tmp-" + str(os.getpid()))
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            os.chmod(temporary, 0o600)
            json.dump(report, handle, indent=2, allow_nan=False)
            handle.write("\n")
        temporary.replace(args.output)
    except OSError:
        if temporary.exists():
            temporary.unlink()
        print("Could not write aggregate soak report.", file=sys.stderr)
        return 1
    print("Soak " + ("passed" if report["passed"] else "failed") + "; aggregate report: " + str(args.output))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
