"""Supervisor checks with synthetic streams and harmless owned child processes."""
import importlib.util
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

SPEC = importlib.util.spec_from_file_location("terrarium_soak", Path(__file__).resolve().parents[1] / "scripts/soak.py")
soak = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = soak
SPEC.loader.exec_module(soak)


def sample():
    return {"version": 1, "timestamp": 1700000000, "interval": 2, "cpu": 20,
            "memory": {"usedBytes": 10, "totalBytes": 100, "percent": 10},
            "network": {"interfaces": ["PRIVATE_INTERFACE"], "rxBytesPerSec": 100, "txBytesPerSec": 0},
            "processes": [{"key": "PRIVATE_PROCESS", "name": "PRIVATE_PROCESS", "count": 1, "cpu": 2,
                           "memoryBytes": 10, "category": "other"}],
            "processesAvailable": True, "processCount": 1, "uptimeSeconds": 10, "errors": []}


def metric(second, phase, **updates):
    animations = int(phase in {"animated", "warmup", "art"})
    postcard_seen = phase in {"postcard", "teardown"}
    value = {"type": "metric", "second": second, "phase": phase, "samples": 100,
            "residents": 7, "notes": 24, "textures": 0 if phase == "teardown" else 14 if phase == "postcard" else 7,
            "transients": 0 if phase == "teardown" else 2, "paints": 300,
            "scenes": 0 if phase == "teardown" else 2 if phase == "postcard" else 1,
            "animatedScenes": animations, "viewLoaded": phase != "teardown", "animationRunning": bool(animations),
            "postcardLoaded": phase == "postcard", "postcardReady": phase == "postcard", "postcardAnimated": False,
            "postcardRequests": int(postcard_seen), "postcardReadyCount": int(postcard_seen),
            "postcardReleases": int(phase == "teardown"), "postcardFrozenChecks": int(postcard_seen),
            "postcardLiveUpdates": int(postcard_seen)}
    value.update(updates)
    return value


class ValidationTests(unittest.TestCase):
    def test_valid_observations_retain_only_counts(self):
        protocol = soak.Protocol()
        protocol.line("observer", "stdout", json.dumps(sample()).encode())
        self.assertEqual(protocol.valid_samples, 1)
        self.assertNotIn("PRIVATE", json.dumps(vars(protocol)))

    def test_observer_workload_retains_only_aggregate_process_and_group_counts(self):
        protocol = soak.Protocol()
        for count, groups in ((7, 1), (40, 3), (20, 2)):
            value = sample()
            value["processCount"] = count
            value["processes"] *= groups
            protocol.line("observer", "stdout", json.dumps(value).encode())
        self.assertEqual(protocol.observer_scale["processCount"], {"samples": 3, "min": 7, "max": 40, "total": 67})
        self.assertEqual(protocol.observer_scale["returnedGroups"], {"samples": 3, "min": 1, "max": 3, "total": 6})
        self.assertNotIn("PRIVATE", json.dumps(vars(protocol)))

    def test_unavailable_processes_are_valid_degraded_observations(self):
        value = sample()
        value.update(processesAvailable=False, errors=["process scan incomplete"])
        protocol = soak.Protocol()
        protocol.line("observer", "stdout", json.dumps(value).encode())
        self.assertEqual(protocol.valid_samples, 1)
        self.assertEqual(protocol.unavailable_samples, 1)
        self.assertEqual(protocol.observer_errors, 1)

    def test_malformed_observations_fail_without_retaining_input(self):
        for mutation in ({"version": True}, {"cpu": float("nan")}, {"processesAvailable": None},
                         {"processes": [{"name": "PRIVATE_PROCESS"}]}, {"errors": ["x" * 81]}):
            with self.subTest(fields=list(mutation)):
                value = sample()
                value.update(mutation)
                with self.assertRaisesRegex(soak.SoakError, "^observer_malformed_sample$"):
                    soak.validate_observation(json.dumps(value))
        with self.assertRaisesRegex(soak.SoakError, "^observer_malformed_sample$"):
            soak.validate_observation("[" * 2000 + "]" * 2000)

    def test_unexpected_qml_diagnostics_fail_without_retaining_text(self):
        protocol = soak.Protocol()
        with self.assertRaisesRegex(soak.SoakError, "view_unexpected_diagnostic"):
            protocol.line("view", "stderr", b"PRIVATE_WARNING_DETAILS")
        self.assertEqual(protocol.qml_diagnostics, 1)
        self.assertNotIn("PRIVATE", json.dumps(vars(protocol)))

    def test_paused_scene_cannot_report_running_animation(self):
        value = metric(1, "hidden")
        value["animationRunning"] = True
        with self.assertRaisesRegex(soak.SoakError, "view_malformed_metric"):
            soak.Protocol().line("view", "stderr", b"qml: SOAK " + json.dumps(value).encode())

    def test_postcard_may_wait_for_painted_readiness_then_release(self):
        protocol = soak.Protocol()
        values = [metric(1, "postcard", postcardReady=False, postcardReadyCount=0,
                         postcardFrozenChecks=0, scenes=1, textures=7),
                  metric(2, "postcard"), metric(3, "teardown")]
        for value in values:
            protocol.line("view", "stderr", b"SOAK " + json.dumps(value).encode())
        self.assertEqual(protocol.maxima["scenes"], 2)
        self.assertEqual(protocol.maxima["textures"], 14)
        self.assertEqual(protocol.postcard_counts["postcardReleases"], 1)

    def test_scene_and_postcard_resource_violations_fail(self):
        for phase, changes in (("postcard", {"scenes": 3}), ("postcard", {"textures": 15}),
                               ("art", {"animatedScenes": 2}), ("postcard", {"postcardAnimated": True}),
                               ("postcard", {"animationRunning": True, "animatedScenes": 1}),
                               ("postcard", {"postcardReady": True, "scenes": 1, "textures": 7}),
                               ("options", {"postcardLoaded": True}), ("art", {"scenes": 2}),
                               ("teardown", {"scenes": 1}), ("postcard", {"postcardReleases": 2})):
            with self.subTest(phase=phase, changes=changes):
                value = metric(1, phase, **changes)
                with self.assertRaisesRegex(soak.SoakError, "view_malformed_metric"):
                    soak.Protocol().line("view", "stderr", b"SOAK " + json.dumps(value).encode())

    def test_postcard_counts_cannot_go_backwards(self):
        protocol = soak.Protocol()
        protocol.line("view", "stderr", b"SOAK " + json.dumps(metric(1, "postcard")).encode())
        with self.assertRaisesRegex(soak.SoakError, "view_malformed_metric"):
            protocol.line("view", "stderr", b"SOAK " + json.dumps(metric(2, "art")).encode())

    def test_completion_requires_observed_teardown(self):
        with self.assertRaisesRegex(soak.SoakError, "view_malformed_metric"):
            soak.Protocol().line("view", "stderr", b'SOAK {"type":"done","viewLoaded":false}')

    def test_owned_pid_identity_change_prevents_measurement(self):
        process = mock.Mock(pid=123)
        child = soak.OwnedChild("view", process, 1, {"ticks": 0}, 0)
        with mock.patch.object(soak, "counter", return_value={"start": 2, "ticks": 0, "rss": 0}):
            with self.assertRaisesRegex(soak.SoakError, "view_identity_changed"):
                child.sample(1, "warmup", "warmup")
        process.terminate.assert_not_called()
        process.kill.assert_not_called()

    def test_window_statistics_do_not_retain_individual_samples(self):
        stats = soak.WindowStats()
        for second in range(10000):
            stats.add(second, 20 + second / 60)
        result = stats.result()
        self.assertEqual(result["samples"], 10000)
        self.assertEqual(result["trendPerMinute"], 1)
        self.assertLess(len(json.dumps(vars(stats))), 350)


class SupervisorTests(unittest.TestCase):
    def test_counter_read_failure_does_not_leak_owned_child_during_cleanup(self):
        child = soak.launch("observer", [sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], os.environ.copy())
        real_counter = soak.counter
        first = True

        def temporary_failure(pid):
            nonlocal first
            if first:
                first = False
                raise soak.SoakError("owned_process_counter_unreadable")
            return real_counter(pid)

        errors = []
        try:
            with mock.patch.object(soak, "counter", side_effect=temporary_failure):
                soak.stop(child, errors)
            self.assertIn("observer_cleanup_counter_unreadable", errors)
            self.assertTrue(child.stopped)
            self.assertEqual(child.process.poll(), 0)
        finally:
            if child.process.poll() is None:
                soak.stop(child, [])

    def run_fakes(self, crash=False, malformed=False, missing_postcard_update=False):
        real_launch = soak.launch
        launched = []
        phases = ["warmup", "animated", "paused", "hidden", "reduced", "journal", "options", "art", "postcard", "teardown"]
        messages = ["SOAK " + json.dumps(metric(i, phase, **({"postcardLiveUpdates": 0} if missing_postcard_update else {})))
                    for i, phase in enumerate(phases)]
        messages.append('SOAK {"type":"done","second":30,"viewLoaded":false}')
        view_script = ("import sys,time\n"
                       "time.sleep(.15)\n"
                       + ("sys.exit(7)\n" if crash else "\n".join("print(" + repr(line) + ", flush=True)" for line in messages)))
        observer_line = "PRIVATE_MALFORMED" if malformed else json.dumps(sample())
        observer_script = ("import sys\n"
                           "for i in range(12): print(" + repr(observer_line) + ", flush=True)\n"
                           "sys.stdin.buffer.read()\n")

        def launch(role, command, env):
            child = real_launch(role, [sys.executable, "-u", "-c", view_script if role == "view" else observer_script], env)
            launched.append(child)
            return child

        with mock.patch.object(soak, "launch", side_effect=launch):
            report = soak.run(30)
        for child in launched:
            self.assertIsNotNone(child.process.poll(), "owned fake child leaked")
            self.assertIsNone(soak.counter(child.process.pid), "owned fake child was not reaped")
        self.assertNotIn("PRIVATE", json.dumps(report))
        return report

    def test_successful_supervision_reaps_both_owned_children(self):
        report = self.run_fakes()
        self.assertTrue(report["passed"], report["errors"])
        self.assertEqual(report["observerValidSamples"], 12)
        self.assertTrue(report["viewTeardownObserved"])
        self.assertEqual(report["viewMaxima"]["textures"], 14)
        self.assertEqual(report["postcardLifecycleCounts"]["postcardReleases"], 1)
        self.assertEqual(report["observerWorkload"]["processCount"], {"samples": 12, "min": 1, "max": 1, "mean": 1})
        self.assertTrue(all(child["stoppedAndReaped"] for child in report["children"].values()))

    def test_postcard_coverage_requires_updates_during_frozen_preview(self):
        report = self.run_fakes(missing_postcard_update=True)
        self.assertFalse(report["passed"])
        self.assertIn("postcard_scenario_coverage_incomplete", report["errors"])

    def test_view_crash_fails_and_cleans_observer(self):
        report = self.run_fakes(crash=True)
        self.assertFalse(report["passed"])
        self.assertIn("view_unexpected_exit", report["errors"])

    def test_malformed_observer_fails_and_cleans_view(self):
        report = self.run_fakes(malformed=True)
        self.assertFalse(report["passed"])
        self.assertIn("observer_malformed_sample", report["errors"])


if __name__ == "__main__":
    unittest.main()
