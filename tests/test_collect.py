#!/usr/bin/env python3
"""Synthetic procfs tests for the read-only telemetry collector."""

from __future__ import annotations

import builtins
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
COLLECT_PATH = ROOT / "scripts" / "collect.py"


def load_collect():
    spec = importlib.util.spec_from_file_location("terrarium_collect", COLLECT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


collect = load_collect()


class Clock:
    def __init__(self, wall: float = 1_700_000_000.0, mono: float = 50.0) -> None:
        self.wall = wall
        self.mono = mono

    def time(self) -> float:
        return self.wall

    def monotonic(self) -> float:
        return self.mono

    def advance(self, seconds: float) -> None:
        self.wall += seconds
        self.mono += seconds


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def make_stat_cpu(user: int, nice: int, system: int, idle: int, iowait: int = 0) -> str:
    rest = f"{user} {nice} {system} {idle} {iowait} 0 0 0 0 0"
    return f"cpu  {rest}\ncpu0 {rest}\n"


def make_meminfo(
    total_kb: int,
    *,
    available_kb: int | None = None,
    free_kb: int | None = None,
    buffers_kb: int = 0,
    cached_kb: int = 0,
    sreclaim_kb: int = 0,
    shmem_kb: int = 0,
) -> str:
    lines = [f"MemTotal:       {total_kb} kB"]
    if free_kb is not None:
        lines.append(f"MemFree:        {free_kb} kB")
    if available_kb is not None:
        lines.append(f"MemAvailable:   {available_kb} kB")
    lines.append(f"Buffers:        {buffers_kb} kB")
    lines.append(f"Cached:         {cached_kb} kB")
    lines.append(f"Shmem:          {shmem_kb} kB")
    lines.append(f"SReclaimable:   {sreclaim_kb} kB")
    return "\n".join(lines) + "\n"


def make_netdev(ifaces: dict[str, tuple[int, int]]) -> str:
    lines = [
        "Inter-|   Receive                                                |  Transmit",
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
    ]
    for name, (rx, tx) in ifaces.items():
        lines.append(
            f"{name}: {rx} 1 0 0 0 0 0 0 {tx} 1 0 0 0 0 0 0"
        )
    return "\n".join(lines) + "\n"


def make_pid_stat(
    pid: int,
    comm: str,
    state: str = "S",
    utime: int = 0,
    stime: int = 0,
    starttime: int = 99,
    rss_pages: int = 0,
    ppid: int = 1,
) -> str:
    fields = [
        state,
        ppid,
        0,
        0,
        0,
        -1,
        0,
        0,
        0,
        0,
        0,
        utime,
        stime,
        0,
        0,
        20,
        0,
        1,
        0,
        starttime,
        0,
        rss_pages,
    ]
    return f"{pid} ({comm}) " + " ".join(str(x) for x in fields) + "\n"


def make_status(
    uid: int,
    rss_kb: int = 0,
    name: str = "proc",
    state: str = "S",
) -> str:
    return (
        f"Name:\t{name}\n"
        f"State:\t{state} (sleeping)\n"
        f"Pid:\t1\n"
        f"Uid:\t{uid}\t{uid}\t{uid}\t{uid}\n"
        f"VmRSS:\t{rss_kb} kB\n"
    )


class ProcFS:
    def __init__(self, root: Path, uid: int = 1000) -> None:
        self.root = root
        self.uid = uid
        (root / "net").mkdir(parents=True, exist_ok=True)
        self.set_cpu(100, 0, 50, 850)
        self.set_mem(total_kb=1_000_000, available_kb=600_000)
        self.set_net({"eth0": (1000, 2000)})
        self.set_uptime(123.5)

    def set_cpu(self, user: int, nice: int, system: int, idle: int, iowait: int = 0) -> None:
        write_text(self.root / "stat", make_stat_cpu(user, nice, system, idle, iowait))

    def set_mem(self, **kwargs) -> None:
        write_text(self.root / "meminfo", make_meminfo(**kwargs))

    def set_net(self, ifaces: dict[str, tuple[int, int]]) -> None:
        write_text(self.root / "net" / "dev", make_netdev(ifaces))

    def set_uptime(self, seconds: float) -> None:
        write_text(self.root / "uptime", f"{seconds} 10.0\n")

    def add_proc(
        self,
        pid: int,
        comm: str,
        *,
        uid: int | None = None,
        state: str = "S",
        utime: int = 0,
        stime: int = 0,
        starttime: int = 99,
        rss_kb: int = 0,
        rss_pages: int = 0,
        with_status: bool = True,
        with_comm: bool = True,
    ) -> Path:
        pid_dir = self.root / str(pid)
        pid_dir.mkdir(parents=True, exist_ok=True)
        write_text(
            pid_dir / "stat",
            make_pid_stat(
                pid,
                comm,
                state=state,
                utime=utime,
                stime=stime,
                starttime=starttime,
                rss_pages=rss_pages,
            ),
        )
        if with_status:
            write_text(
                pid_dir / "status",
                make_status(uid if uid is not None else self.uid, rss_kb, comm, state),
            )
        if with_comm:
            write_text(pid_dir / "comm", comm + "\n")
        return pid_dir

    def remove_proc(self, pid: int) -> None:
        path = self.root / str(pid)
        if path.exists():
            shutil.rmtree(path)


class CollectorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fs = ProcFS(self.root, uid=1000)
        self.clock = Clock()
        self.collector = collect.Collector(
            proc_root=self.root,
            uid=1000,
            self_pid=-1,
            time_fn=self.clock.time,
            monotonic_fn=self.clock.monotonic,
            page_size_bytes=4096,
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def sample_pair(self, advance: float = 2.0) -> tuple[dict, dict]:
        first = self.collector.sample()
        self.clock.advance(advance)
        second = self.collector.sample()
        return first, second


class CpuTests(CollectorTests):
    def test_cpu_null_on_first_sample(self) -> None:
        sample = self.collector.sample()
        self.assertIsNone(sample["cpu"])
        self.assertEqual(sample["interval"], 0)
        self.assertEqual(sample["timestamp"], 1_700_000_000)

    def test_cpu_percent_from_stat_delta(self) -> None:
        # total 1000 -> 1120 (delta 120); idle 850 -> 870 (delta 20) => 83.333...%
        self.fs.set_cpu(100, 0, 50, 850)
        first = self.collector.sample()
        self.assertIsNone(first["cpu"])
        self.fs.set_cpu(180, 0, 70, 870)
        self.clock.advance(2.0)
        second = self.collector.sample()
        self.assertAlmostEqual(second["cpu"], 100.0 * 100.0 / 120.0, places=6)
        self.assertAlmostEqual(second["interval"], 2.0)
        self.assertGreaterEqual(second["cpu"], 0)
        self.assertLessEqual(second["cpu"], 100)

    def test_cpu_null_on_corrupt_stat_not_zero(self) -> None:
        self.collector.sample()
        write_text(self.root / "stat", "not a cpu file\n")
        self.clock.advance(2.0)
        sample = self.collector.sample()
        self.assertIsNone(sample["cpu"])
        self.assertTrue(any("cpu" in err for err in sample["errors"]))
        self.assertNotIn(0, [sample["cpu"]])

    def test_cpu_null_on_counter_reset(self) -> None:
        self.fs.set_cpu(1000, 0, 500, 8000)
        self.collector.sample()
        self.fs.set_cpu(10, 0, 5, 20)
        self.clock.advance(2.0)
        sample = self.collector.sample()
        self.assertIsNone(sample["cpu"])

    def test_cpu_missing_file(self) -> None:
        (self.root / "stat").unlink()
        sample = self.collector.sample()
        self.assertIsNone(sample["cpu"])
        self.assertTrue(sample["errors"])


class MemoryTests(CollectorTests):
    def test_memory_uses_available(self) -> None:
        self.fs.set_mem(total_kb=1000, available_kb=400, free_kb=100)
        sample = self.collector.sample()
        mem = sample["memory"]
        self.assertEqual(mem["totalBytes"], 1000 * 1024)
        self.assertEqual(mem["usedBytes"], 600 * 1024)
        self.assertAlmostEqual(mem["percent"], 60.0)

    def test_memory_fallback_without_available(self) -> None:
        # used = total - free - buffers - cached - sreclaim + shmem
        # 1000 - 100 - 50 - 200 - 25 + 10 = 635 kB
        self.fs.set_mem(
            total_kb=1000,
            free_kb=100,
            buffers_kb=50,
            cached_kb=200,
            sreclaim_kb=25,
            shmem_kb=10,
        )
        sample = self.collector.sample()
        mem = sample["memory"]
        self.assertEqual(mem["usedBytes"], 635 * 1024)
        self.assertEqual(mem["totalBytes"], 1000 * 1024)
        self.assertAlmostEqual(mem["percent"], 63.5)

    def test_memory_percent_null_without_total(self) -> None:
        write_text(self.root / "meminfo", "MemFree: 100 kB\n")
        sample = self.collector.sample()
        self.assertEqual(sample["memory"]["usedBytes"], 0)
        self.assertEqual(sample["memory"]["totalBytes"], 0)
        self.assertIsNone(sample["memory"]["percent"])
        self.assertTrue(any("memory" in err for err in sample["errors"]))


class StatParseTests(unittest.TestCase):
    def test_comm_with_spaces(self) -> None:
        text = make_pid_stat(4242, "Web Content", utime=11, stime=7, starttime=12345)
        parsed = collect.parse_pid_stat(text)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed["comm"], "Web Content")
        self.assertEqual(parsed["ticks"], 18)
        self.assertEqual(parsed["starttime"], 12345)
        self.assertEqual(parsed["pid"], 4242)

    def test_comm_with_closing_parentheses(self) -> None:
        text = make_pid_stat(9, "foo) (bar", utime=3, stime=4, starttime=50)
        parsed = collect.parse_pid_stat(text)
        self.assertEqual(parsed["comm"], "foo) (bar")
        self.assertEqual(parsed["ticks"], 7)
        self.assertEqual(parsed["starttime"], 50)

    def test_corrupt_stat_returns_none(self) -> None:
        self.assertIsNone(collect.parse_pid_stat("nope"))
        self.assertIsNone(collect.parse_pid_stat("1 (incomplete"))
        self.assertIsNone(collect.parse_pid_stat("1 () S"))


class ProcessLifecycleTests(CollectorTests):
    def test_pid_reuse_does_not_use_old_ticks(self) -> None:
        self.fs.set_cpu(0, 0, 0, 100)
        self.fs.add_proc(100, "firefox", utime=1000, stime=0, starttime=10, rss_kb=100)
        self.collector.sample()
        self.fs.set_cpu(0, 0, 0, 200)
        self.fs.add_proc(100, "firefox", utime=5000, stime=0, starttime=999, rss_kb=100)
        self.clock.advance(2.0)
        sample = self.collector.sample()
        groups = {g["key"]: g for g in sample["processes"]}
        self.assertIn("firefox", groups)
        self.assertIsNone(groups["firefox"]["cpu"])

    def test_same_starttime_computes_cpu(self) -> None:
        self.fs.set_cpu(0, 0, 0, 100)
        self.fs.add_proc(100, "firefox", utime=10, stime=0, starttime=10, rss_kb=50)
        self.collector.sample()
        self.fs.set_cpu(50, 0, 50, 100)  # total delta 100
        self.fs.add_proc(100, "firefox", utime=30, stime=0, starttime=10, rss_kb=50)
        self.clock.advance(2.0)
        sample = self.collector.sample()
        groups = {g["key"]: g for g in sample["processes"]}
        self.assertAlmostEqual(groups["firefox"]["cpu"], 20.0)

    def test_process_disappearance(self) -> None:
        self.fs.add_proc(20, "nvim", rss_kb=10)
        self.fs.add_proc(21, "firefox", rss_kb=20)
        first = self.collector.sample()
        self.assertEqual(first["processCount"], 2)
        self.fs.remove_proc(21)
        self.clock.advance(2.0)
        second = self.collector.sample()
        self.assertEqual(second["processCount"], 1)
        keys = {g["key"] for g in second["processes"]}
        self.assertEqual(keys, {"nvim"})

    def test_zombie_excluded(self) -> None:
        self.fs.add_proc(30, "defunct", state="Z", rss_kb=8)
        self.fs.add_proc(31, "bash", state="S", rss_kb=8)
        sample = self.collector.sample()
        self.assertEqual(sample["processCount"], 1)
        self.assertEqual(sample["processes"][0]["key"], "bash")

    def test_other_uid_excluded(self) -> None:
        self.fs.add_proc(40, "root-proc", uid=0, rss_kb=99)
        self.fs.add_proc(41, "mine", uid=1000, rss_kb=10)
        sample = self.collector.sample()
        self.assertEqual(sample["processCount"], 1)
        self.assertEqual(sample["processes"][0]["key"], "mine")

    def test_self_pid_excluded(self) -> None:
        self.fs.add_proc(55, "collector", rss_kb=10)
        self.fs.add_proc(56, "keep", rss_kb=10)
        c = collect.Collector(
            proc_root=self.root,
            uid=1000,
            self_pid=55,
            time_fn=self.clock.time,
            monotonic_fn=self.clock.monotonic,
        )
        sample = c.sample()
        self.assertEqual(sample["processCount"], 1)
        self.assertEqual(sample["processes"][0]["key"], "keep")

    def test_uid_gating_uses_status_not_host_uid(self) -> None:
        self.fs.add_proc(70, "alien", uid=2000, rss_kb=40)
        self.fs.add_proc(71, "local", uid=1000, rss_kb=40)
        sample = self.collector.sample()
        self.assertEqual(sample["processCount"], 1)
        self.assertEqual(sample["processes"][0]["name"], "local")

    def test_group_count_without_pid_arrays(self) -> None:
        self.fs.add_proc(80, "firefox", rss_kb=10)
        self.fs.add_proc(81, "firefox", rss_kb=15)
        self.fs.add_proc(82, "Firefox", rss_kb=5)
        sample = self.collector.sample()
        self.assertEqual(sample["processCount"], 3)
        group = sample["processes"][0]
        self.assertEqual(group["key"], "firefox")
        self.assertEqual(group["count"], 3)
        self.assertEqual(group["memoryBytes"], 30 * 1024)
        self.assertNotIn("pids", group)
        self.assertNotIn("pid", group)
        dumped = json.dumps(sample)
        self.assertNotIn('"pid"', dumped)

    def test_permission_denied_process_ignored(self) -> None:
        pid_dir = self.fs.add_proc(90, "secret", rss_kb=12)
        stat_path = pid_dir / "stat"
        os.chmod(stat_path, 0)
        try:
            if os.access(stat_path, os.R_OK):
                self.skipTest("process is readable despite mode 0")
            sample = self.collector.sample()
            self.assertEqual(sample["processCount"], 0)
            self.assertEqual(sample["processes"], [])
        finally:
            os.chmod(stat_path, 0o644)

    def test_corrupt_process_stat_ignored(self) -> None:
        self.fs.add_proc(91, "ok", rss_kb=4)
        write_text(self.root / "92" / "stat", "garbage (broken\n")
        write_text(self.root / "92" / "status", make_status(1000, 4, "broken"))
        sample = self.collector.sample()
        self.assertEqual(sample["processCount"], 1)
        self.assertEqual(sample["processes"][0]["key"], "ok")

    def test_process_cpu_null_initially(self) -> None:
        self.fs.add_proc(93, "nvim", utime=10, rss_kb=8)
        sample = self.collector.sample()
        self.assertIsNone(sample["processes"][0]["cpu"])


class NetworkTests(CollectorTests):
    def test_network_rates(self) -> None:
        self.fs.set_net({"eth0": (1000, 2000)})
        first = self.collector.sample()
        self.assertIsNone(first["network"]["rxBytesPerSec"])
        self.assertIsNone(first["network"]["txBytesPerSec"])
        self.assertEqual(first["network"]["interfaces"], ["eth0"])
        self.fs.set_net({"eth0": (5000, 2600)})
        self.clock.advance(2.0)
        second = self.collector.sample()
        self.assertAlmostEqual(second["network"]["rxBytesPerSec"], 2000.0)
        self.assertAlmostEqual(second["network"]["txBytesPerSec"], 300.0)

    def test_network_counter_reset_no_spike(self) -> None:
        self.fs.set_net({"eth0": (10_000, 10_000)})
        self.collector.sample()
        self.fs.set_net({"eth0": (5, 10_400)})
        self.clock.advance(2.0)
        sample = self.collector.sample()
        self.assertAlmostEqual(sample["network"]["rxBytesPerSec"], 0.0)
        self.assertAlmostEqual(sample["network"]["txBytesPerSec"], 200.0)

    def test_interface_arrival_no_spike(self) -> None:
        self.fs.set_net({"eth0": (1000, 1000)})
        self.collector.sample()
        self.fs.set_net({"wlan0": (9_000_000, 8_000_000)})
        self.clock.advance(2.0)
        sample = self.collector.sample()
        self.assertAlmostEqual(sample["network"]["rxBytesPerSec"], 0.0)
        self.assertAlmostEqual(sample["network"]["txBytesPerSec"], 0.0)
        self.assertEqual(sample["network"]["interfaces"], ["wlan0"])

    def test_interface_departure_does_not_keep_old_rates(self) -> None:
        self.fs.set_net({"eth0": (1000, 1000), "wlan0": (500, 500)})
        self.collector.sample()
        self.fs.set_net({"wlan0": (1500, 700)})
        self.clock.advance(2.0)
        sample = self.collector.sample()
        self.assertAlmostEqual(sample["network"]["rxBytesPerSec"], 500.0)
        self.assertAlmostEqual(sample["network"]["txBytesPerSec"], 100.0)
        self.assertEqual(sample["network"]["interfaces"], ["wlan0"])

    def test_skip_virtual_interfaces(self) -> None:
        self.fs.set_net(
            {
                "lo": (999999, 999999),
                "veth0abc": (888888, 888888),
                "docker0": (777777, 777777),
                "br-1234ab": (666666, 666666),
                "eth0": (100, 200),
            }
        )
        sample = self.collector.sample()
        self.assertEqual(sample["network"]["interfaces"], ["eth0"])

    def test_unreadable_network_is_null_not_zero(self) -> None:
        self.collector.sample()
        (self.root / "net" / "dev").unlink()
        self.clock.advance(2.0)
        sample = self.collector.sample()
        self.assertIsNone(sample["network"]["rxBytesPerSec"])
        self.assertIsNone(sample["network"]["txBytesPerSec"])


class SchemaAndPrivacyTests(CollectorTests):
    REQUIRED = (
        "version",
        "timestamp",
        "interval",
        "cpu",
        "memory",
        "network",
        "processes",
        "processCount",
        "uptimeSeconds",
        "errors",
    )

    def test_schema_keys_and_version(self) -> None:
        sample = self.collector.sample()
        self.assertEqual(list(sample.keys()), list(self.REQUIRED))
        self.assertEqual(sample["version"], 1)
        self.assertEqual(sample["uptimeSeconds"], 123.5)
        self.assertEqual(set(sample["memory"]), {"usedBytes", "totalBytes", "percent"})
        self.assertEqual(
            set(sample["network"]),
            {"rxBytesPerSec", "txBytesPerSec", "interfaces"},
        )

    def test_errors_omit_paths(self) -> None:
        secret = self.root / "secret-path-xyz"
        # Force several unreadable counters while using a distinctive root.
        (self.root / "stat").unlink()
        (self.root / "meminfo").unlink()
        sample = self.collector.sample()
        blob = json.dumps(sample)
        self.assertNotIn(str(self.root), blob)
        self.assertNotIn("secret-path-xyz", blob)
        for err in sample["errors"]:
            self.assertNotIn("/", err)
            self.assertLessEqual(len(err), 80)

    def test_never_reads_cmdline_or_environ(self) -> None:
        self.fs.add_proc(101, "firefox", rss_kb=10)
        write_text(self.root / "101" / "cmdline", "/usr/lib/firefox/firefox\x00--secret\n")
        write_text(self.root / "101" / "environ", "TOKEN=super-secret\n")
        opened: list[str] = []
        real_open = builtins.open

        def spy(path, *args, **kwargs):
            opened.append(str(path))
            return real_open(path, *args, **kwargs)

        with mock.patch("builtins.open", spy):
            self.collector.sample()
        joined = "\n".join(opened)
        self.assertNotIn("cmdline", joined)
        self.assertNotIn("environ", joined)

    def test_name_sanitized_and_truncated(self) -> None:
        noisy = "fi\x07re" + ("x" * 80) + "\x00bin"
        self.fs.add_proc(110, noisy, rss_kb=1)
        sample = self.collector.sample()
        name = sample["processes"][0]["name"]
        self.assertNotIn("\x07", name)
        self.assertLessEqual(len(name), 64)
        self.assertTrue(name.startswith("firex"))

    def test_categories(self) -> None:
        cases = {
            "firefox": "browser",
            "Web Content": "browser",
            "nvim": "editor",
            "alacritty": "terminal",
            "claude": "agent",
            "mpv": "media",
            "systemd": "system",
            "python3": "other",
        }
        for i, (comm, category) in enumerate(cases.items(), start=200):
            self.fs.add_proc(i, comm, rss_kb=1)
        sample = self.collector.sample()
        got = {g["name"]: g["category"] for g in sample["processes"]}
        # python3 / nvim / etc. may be truncated from ranking if more than 7,
        # so also check categorize() directly and groups that survived.
        for comm, category in cases.items():
            self.assertEqual(collect.categorize(comm), category)
        for name, category in got.items():
            self.assertIn(category, collect.CATEGORIES)

    def test_top_seven_groups_but_count_all(self) -> None:
        for i in range(10):
            self.fs.add_proc(300 + i, f"app{i}", rss_kb=10 * (i + 1))
        sample = self.collector.sample()
        self.assertEqual(sample["processCount"], 10)
        self.assertEqual(len(sample["processes"]), 7)
        # Highest RSS should rank first when cpu is null.
        self.assertEqual(sample["processes"][0]["key"], "app9")

    def test_initial_deltas_unavailable(self) -> None:
        self.fs.add_proc(400, "firefox", utime=9, rss_kb=8)
        sample = collect.collect_once(self.root, uid=1000, self_pid=-1)
        self.assertIsNone(sample["cpu"])
        self.assertIsNone(sample["network"]["rxBytesPerSec"])
        self.assertIsNone(sample["network"]["txBytesPerSec"])
        self.assertEqual(sample["interval"], 0)
        if sample["processes"]:
            self.assertIsNone(sample["processes"][0]["cpu"])


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fs = ProcFS(self.root, uid=os.getuid())
        self.fs.add_proc(12, "nvim", uid=os.getuid(), rss_kb=8)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_cli(self, args: list[str], timeout: float = 5.0) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-u", str(COLLECT_PATH), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    def test_once_emits_one_json_line(self) -> None:
        result = self.run_cli(["--once", "--proc-root", str(self.root)])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1)
        data = json.loads(lines[0])
        self.assertEqual(data["version"], 1)
        self.assertIsNone(data["cpu"])
        self.assertIsInstance(data["memory"]["usedBytes"], int)
        self.assertIsInstance(data["processCount"], int)
        self.assertIsInstance(data["errors"], list)
        self.assertEqual(data["interval"], 0)
        self.assertNotIn("\n", lines[0])

    def test_once_does_not_sleep(self) -> None:
        import time as time_mod

        started = time_mod.monotonic()
        result = self.run_cli(["--once", "--interval", "60", "--proc-root", str(self.root)])
        elapsed = time_mod.monotonic() - started
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(elapsed, 1.5)

    def test_malformed_interval_rejected(self) -> None:
        for value in ("0", "61", "-1", "foo", "100"):
            result = self.run_cli(["--interval", value, "--once", "--proc-root", str(self.root)])
            self.assertNotEqual(result.returncode, 0, value)
            self.assertFalse(result.stdout.strip())

    def test_interval_bounds_accepted(self) -> None:
        for value in ("1", "2", "60"):
            result = self.run_cli(["--once", "--interval", value, "--proc-root", str(self.root)])
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_stream_stops_on_stdin_eof(self) -> None:
        proc = subprocess.Popen(
            [
                sys.executable,
                "-u",
                str(COLLECT_PATH),
                "--interval",
                "1",
                "--proc-root",
                str(self.root),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            proc.stdin.close()
            out, err = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            self.fail("collector did not exit after stdin EOF")
        self.assertEqual(proc.returncode, 0, err)
        lines = [ln for ln in out.splitlines() if ln.strip()]
        self.assertGreaterEqual(len(lines), 1)
        json.loads(lines[0])

    def test_main_once_via_import(self) -> None:
        buf = io.StringIO()
        with mock.patch("sys.stdout", buf):
            rc = collect.main(["--once", "--proc-root", str(self.root)])
        self.assertEqual(rc, 0)
        data = json.loads(buf.getvalue().strip())
        self.assertEqual(data["version"], 1)


class WaitAndArgparseTests(unittest.TestCase):
    def test_wait_returns_immediately_when_seconds_non_positive(self) -> None:
        state = collect.RunState()
        self.assertFalse(collect.wait_for_stop(0, state, None))
        self.assertFalse(collect.wait_for_stop(-1, state, None))

    def test_wait_honors_stop_flag(self) -> None:
        state = collect.RunState()
        state.stop = True
        self.assertTrue(collect.wait_for_stop(30, state, None))

    def test_interval_type_rejects_nan(self) -> None:
        parser = collect.build_parser()
        stderr = io.StringIO()
        with mock.patch("sys.stderr", stderr):
            with self.assertRaises(SystemExit):
                parser.parse_args(["--interval", "nan"])


if __name__ == "__main__":
    unittest.main()
