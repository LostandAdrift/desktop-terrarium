"""Native benchmark validation with synthetic states/counters; no desktop access."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("terrarium_benchmark", Path(__file__).resolve().parents[1] / "scripts/benchmark.py")
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


def state(phase="animatedDemo", **updates):
    value = {"screenName": "PRIVATE_DISPLAY", "opened": True, "demo": True,
             "section": "garden", "reducedMotion": False, "animationRunning": True,
             "collectorRunning": False, "collectorPid": 0, "watcherCount": 0,
             "locked": False, "ambient": False, "ambientVisible": False,
             "exportBusy": False, "clockRunning": True, "residents": 7,
             "stale": False, "liveSamples": 4, "exportPath": "/PRIVATE_LOCATION"}
    value.update(benchmark.PHASES[phase])
    value["clockRunning"] = value["opened"]
    if value["collectorRunning"]:
        value.update(collectorPid=202, watcherCount=1)
    value.update(updates)
    return value


class Clock:
    now = 0

    def sleep(self, seconds):
        self.now += seconds

    def counter(self, pid):
        return {"starttime": pid * 10, "ticks": int(self.now * benchmark.HZ / 4),
                "rss": 10485760, "parent": 101 if pid == 202 else 1}


class FakeNative:
    pid = 101

    def __init__(self, value):
        self.value = value
        self.identity = Clock().counter(self.pid)
        self.calls = []

    def states(self):
        return [copy.deepcopy(self.value)]

    def call(self, *args):
        self.calls.append(args)
        if args[0] == "shell":
            self.value["opened"] = args[1] == "summon"
        elif args[1] in ("demo", "ambient", "motion"):
            key = "reducedMotion" if args[1] == "motion" else args[1]
            self.value[key] = not self.value[key]
        elif args[1] == "section":
            self.value["section"] = args[2]
        return ""


class BenchmarkTests(unittest.TestCase):
    def test_discovery_rejects_unrelated_or_ambiguous_quickshells(self):
        config = Path("/synthetic/omarchy/shell/shell.qml")
        owned = {"config_path": str(config), "pid": 101}
        self.assertEqual(benchmark.select_shell([owned], config), 101)
        for entries in ([], [owned, owned], [{"pid": True, "config_path": str(config)}],
                        [{"pid": 102, "config_path": "/unrelated/soak.qml"}]):
            with self.subTest(entries=entries), self.assertRaises(benchmark.BenchmarkError):
                benchmark.select_shell(entries, config)

    def test_stat_parsing_and_pid_reuse_detection_discard_process_names(self):
        fields = ["0"] * 22
        fields[1], fields[11], fields[12], fields[19], fields[21] = "101", "20", "3", "456", "40"
        parsed = benchmark.parse_counter("202 (PRIVATE (name)) " + " ".join(fields))
        self.assertEqual(parsed, {"parent": 101, "ticks": 23, "starttime": 456, "rss": 40 * benchmark.PAGE})
        for mutation in ({"starttime": 457}, {"ticks": 22}):
            with self.assertRaises(benchmark.BenchmarkError):
                benchmark.check_identity(parsed, dict(parsed, **mutation))
        self.assertNotIn("PRIVATE", json.dumps(parsed))

    def test_phase_validation_rejects_dismissal_wrong_section_and_other_animation(self):
        for mutation in ({"opened": False}, {"demo": False}, {"animationRunning": False},
                         {"section": "options"}, {"reducedMotion": True}, {"locked": True}):
            with self.subTest(mutation=mutation), self.assertRaises(benchmark.BenchmarkError):
                benchmark.validate_phase([state(**mutation)], "animatedDemo", "PRIVATE_DISPLAY")
        with self.assertRaisesRegex(benchmark.BenchmarkError, "other_panel_active"):
            benchmark.validate_phase([state(), state("closed", screenName="SECOND", animationRunning=True)], "animatedDemo", "PRIVATE_DISPLAY")
        benchmark.validate_phase([state("options")], "options", "PRIVATE_DISPLAY")
        benchmark.validate_phase([state("art")], "art", "PRIVATE_DISPLAY")

    def test_closed_phase_detects_state_changes_and_live_observer_requires_single_owner(self):
        closed = state("closed")
        baseline = [(closed["screenName"], closed["demo"], closed["section"], closed["reducedMotion"])]
        benchmark.validate_phase([closed], "closed", closed_state=baseline)
        with self.assertRaisesRegex(benchmark.BenchmarkError, "closed_settings_changed"):
            benchmark.validate_phase([dict(closed, section="guide")], "closed", closed_state=baseline)
        for mutation in ({"watcherCount": 2}, {"collectorPid": 203}, {"stale": True}, {"liveSamples": 0}):
            with self.subTest(mutation=mutation), self.assertRaises(benchmark.BenchmarkError):
                benchmark.validate_phase([state("liveStillObserverBaseline", **mutation)], "liveStillObserverBaseline", "PRIVATE_DISPLAY", 202)

    def measure(self, native, phase="animatedDemo", counter=None):
        clock = Clock()
        with mock.patch.object(benchmark.time, "monotonic", side_effect=lambda: clock.now), \
             mock.patch.object(benchmark.time, "sleep", side_effect=clock.sleep), \
             mock.patch.object(benchmark, "counter", side_effect=counter or clock.counter):
            return benchmark.measure(native, phase, 2, "PRIVATE_DISPLAY")

    def test_valid_report_contains_only_labeled_numeric_counters(self):
        report = self.measure(FakeNative(state()))
        self.assertTrue(report["valid"])
        self.assertEqual(report["measuredSeconds"], 2)
        self.assertGreaterEqual(report["stateChecks"], 5)
        measured = report["processes"]["omarchyShell"]
        self.assertEqual(measured["cpuPercentOfOneCore"], 25)
        self.assertEqual(measured["starttimeTicks"], 1010)
        self.assertNotIn("PRIVATE", json.dumps(report))

    def test_dismissal_midmeasurement_invalidates_all_resource_numbers(self):
        native = FakeNative(state())
        native.states = mock.Mock(side_effect=[[state()], [state()], [state(opened=False)]])
        report = self.measure(native)
        self.assertFalse(report["valid"])
        self.assertEqual(report["reason"], "panel_not_uniquely_open")
        self.assertNotIn("processes", report)
        self.assertNotIn("cpuPercent", json.dumps(report))

    def test_reused_pid_invalidates_all_resource_numbers(self):
        native = FakeNative(state())
        calls = 0

        def reused(pid):
            nonlocal calls
            calls += 1
            return dict(native.identity, starttime=1010 if calls == 1 else 1011)

        report = self.measure(native, counter=reused)
        self.assertEqual(report["reason"], "process_identity_changed")
        self.assertNotIn("processes", report)

    def test_owned_observer_baseline_requires_parent_and_advancing_samples(self):
        native = FakeNative(state("liveStillObserverBaseline"))
        report = self.measure(native, "liveStillObserverBaseline")
        self.assertEqual(report["reason"], "observer_samples_did_not_advance")
        self.assertNotIn("processes", report)
        count = 0

        def observing():
            nonlocal count
            count += 1
            return [state("liveStillObserverBaseline", liveSamples=4 + count)]

        native.states = observing
        report = self.measure(native, "liveStillObserverBaseline")
        self.assertTrue(report["valid"])
        self.assertEqual(set(report["processes"]), {"omarchyShell", "ownedObserver"})
        clock = Clock()
        report = self.measure(native, "liveStillObserverBaseline", lambda pid: dict(clock.counter(pid), parent=999))
        self.assertEqual(report["reason"], "observer_not_owned_by_shell")
        self.assertNotIn("processes", report)

    def test_invalid_phase_stops_run_and_restores_original_preferences_and_section(self):
        original = state("closed", section="guide", demo=False, ambient=True, reducedMotion=True)
        native = FakeNative(copy.deepcopy(original))
        with mock.patch.object(benchmark, "Native", return_value=native), \
             mock.patch.object(benchmark, "measure", side_effect=[{"valid": True}, {"valid": True}, {"valid": False, "reason": "phase_state_changed"}]):
            report = benchmark.run(5)
        self.assertFalse(report["valid"])
        self.assertTrue(report["restored"])
        self.assertEqual(native.value, original)
        self.assertEqual(report["phases"]["art"]["reason"], "not_run_after_invalid_phase")
        self.assertNotIn("PRIVATE", json.dumps(report))

    def test_active_postcard_is_refused_before_any_mutation(self):
        native = FakeNative(state(section="postcard"))
        with mock.patch.object(benchmark, "Native", return_value=native), self.assertRaises(benchmark.BenchmarkError):
            benchmark.run(5)
        self.assertEqual(native.calls, [])


if __name__ == "__main__":
    unittest.main()
