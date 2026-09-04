#!/usr/bin/env python3
"""Read-only Linux telemetry collector. Emits one NDJSON object per sample."""

from __future__ import annotations

import argparse
import errno
import json
import math
import os
import select
import signal
import stat
import sys
import time
from pathlib import Path

VERSION = 1
DEFAULT_INTERVAL = 2.0
MIN_INTERVAL = 1.0
MAX_INTERVAL = 60.0
MAX_NAME_LEN = 64
MAX_GROUPS = 7
MAX_ERRORS = 8
MAX_ERROR_LEN = 80
MAX_SCAN_PIDS = 4096
MAX_IFACES = 64
MAX_FILE_BYTES = 65536
PAGE_SIZE_FALLBACK = 4096

CATEGORIES = ("browser", "editor", "terminal", "agent", "media", "system", "other")

# Exact comm tokens. Prefix match (token + -_. ) is applied only for tokens
# of length >= 4 so short names cannot swallow unrelated processes.
_BROWSER = frozenset(
    {
        "firefox",
        "firefox-bin",
        "chrome",
        "chromium",
        "brave",
        "brave-browser",
        "vivaldi",
        "vivaldi-bin",
        "opera",
        "epiphany",
        "librewolf",
        "qutebrowser",
        "falkon",
        "midori",
        "seamonkey",
        "msedge",
        "microsoft-edge",
        "thorium",
        "waterfox",
        "palemoon",
        "icecat",
        "zen",
        "zen-bin",
        "floorp",
        "navigator",
        "web-content",
        "webextensions",
        "webkitwebproces",
        "webkitnetworkpr",
        "privileged-cont",
        "isolated-web-co",
        "gnome-www-browse",
    }
)
_EDITOR = frozenset(
    {
        "code",
        "code-oss",
        "codium",
        "vscodium",
        "cursor",
        "vim",
        "nvim",
        "gvim",
        "emacs",
        "gedit",
        "kate",
        "nano",
        "helix",
        "kakoune",
        "subl",
        "sublime_text",
        "atom",
        "geany",
        "mousepad",
        "leafpad",
        "zed",
        "lapce",
        "notepadqq",
        "rstudio",
        "idea",
        "pycharm",
        "goland",
        "clion",
        "webstorm",
        "phpstorm",
        "rider",
        "studio64",
        "android-studio",
        "xed",
        "pluma",
        "micro",
        "neovim",
        "hx",
        "vi",
        "kak",
    }
)
_TERMINAL = frozenset(
    {
        "alacritty",
        "kitty",
        "foot",
        "footclient",
        "ghostty",
        "wezterm",
        "konsole",
        "gnome-terminal",
        "xfce4-terminal",
        "tilix",
        "terminator",
        "urxvt",
        "rxvt",
        "xterm",
        "ptyxis",
        "qterminal",
        "lxterminal",
        "terminology",
        "yakuake",
        "guake",
        "tilda",
        "tmux",
        "screen",
        "rio",
        "contour",
        "kgx",
        "st",
        "warp",
        "hyper",
    }
)
_AGENT = frozenset(
    {
        "grok",
        "claude",
        "claude-code",
        "copilot",
        "aider",
        "gemini",
        "gemini-cli",
        "ollama",
        "chatgpt",
        "codex",
        "opencode",
        "cody",
        "tabnine",
        "codeium",
        "windsurf",
        "cline",
        "crush",
        "goose",
        "cursor-agent",
        "copilot-agent",
        "qwen",
        "lmstudio",
        "lm-studio",
        "anthropic",
        "openai-codex",
        "amp",
    }
)
_MEDIA = frozenset(
    {
        "mpv",
        "vlc",
        "spotify",
        "rhythmbox",
        "clementine",
        "strawberry",
        "audacious",
        "cmus",
        "mpd",
        "kodi",
        "totem",
        "celluloid",
        "haruna",
        "amberol",
        "lollypop",
        "elisa",
        "deadbeef",
        "mplayer",
        "smplayer",
        "obs",
        "obs-studio",
        "ffmpeg",
        "ffplay",
        "cheese",
        "plex",
        "jellyfin",
        "spotifyd",
        "ncspot",
        "gst-launch",
        "pw-play",
    }
)
_SYSTEM = frozenset(
    {
        "systemd",
        "init",
        "kthreadd",
        "dbus-daemon",
        "dbus-broker",
        "pulseaudio",
        "pipewire",
        "wireplumber",
        "hyprland",
        "xwayland",
        "xorg",
        "gnome-shell",
        "kwin",
        "kwin_wayland",
        "plasmashell",
        "networkmanager",
        "udisksd",
        "polkitd",
        "polkit-agent-hel",
        "rtkit-daemon",
        "bluetoothd",
        "cupsd",
        "sshd",
        "cron",
        "crond",
        "udevd",
        "systemd-udevd",
        "gvfsd",
        "sddm",
        "gdm",
        "lightdm",
        "greetd",
        "seatd",
        "login",
        "hypridle",
        "hyprlock",
        "waybar",
        "quickshell",
        "swww",
        "swaybg",
        "xdg-desktop-por",
        "xdg-document-po",
        "xdg-permission-",
        "gnome-keyring-d",
        "kwalletd5",
        "kwalletd6",
        "at-spi-bus-laun",
    }
)


class RunState:
    def __init__(self) -> None:
        self.stop = False


class StopStreaming(SystemExit):
    """Unwind an in-flight read immediately on an intentional stop signal.

    This bypasses the sample-error handler: cancellation is not missing data.
    """


def sanitize_name(value: str | None) -> str:
    if not value:
        return "unknown"
    chars: list[str] = []
    for ch in value:
        o = ord(ch)
        if o < 32 or o == 127:
            continue
        if not ch.isprintable():
            continue
        chars.append(ch)
        if len(chars) >= MAX_NAME_LEN:
            break
    out = "".join(chars).strip()
    return out[:MAX_NAME_LEN] if out else "unknown"


def _norm_key(name: str) -> str:
    return sanitize_name(name).lower()


def _token_match(name: str, tokens: frozenset[str]) -> bool:
    if name in tokens:
        return True
    for tok in tokens:
        if len(tok) < 4:
            continue
        if (
            name.startswith(tok + "-")
            or name.startswith(tok + "_")
            or name.startswith(tok + ".")
        ):
            return True
    return False


def categorize(name: str) -> str:
    n = _norm_key(name)
    spaced = n.replace("_", " ")
    if (
        _token_match(n, _BROWSER)
        or n.startswith("webkit")
        or "web content" in spaced
        or n.startswith("isolated-web")
        or n.startswith("privileged-cont")
    ):
        return "browser"
    if _token_match(n, _EDITOR):
        return "editor"
    if _token_match(n, _TERMINAL):
        return "terminal"
    if _token_match(n, _AGENT):
        return "agent"
    if _token_match(n, _MEDIA):
        return "media"
    if _token_match(n, _SYSTEM) or n.startswith("systemd-") or n.startswith("xdg-"):
        return "system"
    return "other"


def skip_interface(name: str) -> bool:
    n = name.strip().lower()
    if n == "lo" or n.startswith("lo:"):
        return True
    if n.startswith("veth"):
        return True
    if n.startswith("docker"):
        return True
    if n.startswith("br-"):
        return True
    return False


def clamp(value: float, lo: float, hi: float) -> float:
    if value < lo:
        return lo
    if value > hi:
        return hi
    return value


def add_error(errors: list[str], message: str) -> None:
    text = sanitize_name(message)[:MAX_ERROR_LEN]
    if not text:
        return
    if text in errors:
        return
    if len(errors) >= MAX_ERRORS:
        return
    errors.append(text)


def read_text(path: Path, max_bytes: int = MAX_FILE_BYTES) -> str | None:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            return fh.read(max_bytes)
    except OSError:
        return None


def page_size() -> int:
    try:
        value = int(os.sysconf("SC_PAGE_SIZE"))
        if value > 0:
            return value
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    return PAGE_SIZE_FALLBACK


def parse_proc_stat_cpu(text: str) -> tuple[int, int] | None:
    for line in text.splitlines():
        if not line.startswith("cpu "):
            continue
        parts = line.split()
        if len(parts) < 5:
            return None
        try:
            nums = [int(x) for x in parts[1:]]
        except ValueError:
            return None
        user, nice, system, idle = nums[0], nums[1], nums[2], nums[3]
        iowait = nums[4] if len(nums) > 4 else 0
        irq = nums[5] if len(nums) > 5 else 0
        softirq = nums[6] if len(nums) > 6 else 0
        steal = nums[7] if len(nums) > 7 else 0
        # guest / guest_nice are already counted inside user / nice.
        idle_all = idle + iowait
        non_idle = user + nice + system + irq + softirq + steal
        total = idle_all + non_idle
        if total < 0 or idle_all < 0:
            return None
        return total, idle_all
    return None


def cpu_percent(prev_total: int, prev_idle: int, total: int, idle: int) -> float | None:
    if total < prev_total:
        return None
    delta_total = total - prev_total
    if delta_total <= 0:
        return None
    delta_idle = idle - prev_idle
    if delta_idle < 0:
        delta_idle = 0
    if delta_idle > delta_total:
        delta_idle = delta_total
    return clamp(100.0 * (delta_total - delta_idle) / delta_total, 0.0, 100.0)


def parse_meminfo(text: str) -> tuple[int, int, float | None] | None:
    fields: dict[str, int] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, rest = line.split(":", 1)
        parts = rest.split()
        if not parts:
            continue
        try:
            raw = int(parts[0])
        except ValueError:
            continue
        if raw < 0:
            continue
        unit = parts[1].lower() if len(parts) > 1 else "kb"
        if unit in ("kb", "kib"):
            bytes_ = raw * 1024
        elif unit in ("mb", "mib"):
            bytes_ = raw * 1024 * 1024
        elif unit in ("b", "byte", "bytes"):
            bytes_ = raw
        else:
            bytes_ = raw * 1024
        fields[key.strip()] = bytes_
    total = fields.get("MemTotal")
    if not total:
        return None
    if "MemAvailable" in fields:
        used = total - fields["MemAvailable"]
    else:
        free = fields.get("MemFree", 0)
        buffers = fields.get("Buffers", 0)
        cached = fields.get("Cached", 0)
        sreclaim = fields.get("SReclaimable", 0)
        shmem = fields.get("Shmem", 0)
        used = total - free - buffers - cached - sreclaim + shmem
    used = int(used)
    if used < 0:
        used = 0
    if used > total:
        used = total
    percent = clamp(100.0 * used / total, 0.0, 100.0) if total else None
    return used, int(total), percent


def parse_netdev(text: str) -> dict[str, tuple[int, int]]:
    result: dict[str, tuple[int, int]] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        raw_name, rest = line.split(":", 1)
        name = sanitize_name(raw_name.strip())
        if not name or name == "unknown":
            continue
        lower = raw_name.strip()
        if skip_interface(lower):
            continue
        if skip_interface(name):
            continue
        parts = rest.split()
        if len(parts) < 9:
            continue
        try:
            rx = int(parts[0])
            tx = int(parts[8])
        except ValueError:
            continue
        if rx < 0 or tx < 0:
            continue
        key = name.lower()
        if key in result:
            prev_rx, prev_tx = result[key]
            result[key] = (prev_rx + rx, prev_tx + tx)
        else:
            result[key] = (rx, tx)
        if len(result) >= MAX_IFACES:
            break
    return result


def parse_uptime(text: str) -> float | None:
    parts = text.split()
    if not parts:
        return None
    try:
        value = float(parts[0])
    except ValueError:
        return None
    if value < 0 or not math.isfinite(value):
        return None
    return value


def parse_pid_stat(text: str) -> dict | None:
    lparen = text.find("(")
    rparen = text.rfind(")")
    if lparen < 0 or rparen < 0 or rparen <= lparen:
        return None
    pid_s = text[:lparen].strip()
    comm = text[lparen + 1 : rparen]
    rest = text[rparen + 1 :].strip().split()
    if len(rest) < 20:
        return None
    try:
        pid = int(pid_s)
        state = rest[0]
        utime = int(rest[11])
        stime = int(rest[12])
        starttime = int(rest[19])
        rss_pages = int(rest[21]) if len(rest) > 21 else None
    except (ValueError, IndexError):
        return None
    if pid < 0 or utime < 0 or stime < 0 or starttime < 0:
        return None
    if not state:
        return None
    ticks = utime + stime
    if ticks < 0:
        return None
    return {
        "pid": pid,
        "comm": comm,
        "state": state[0],
        "ticks": ticks,
        "starttime": starttime,
        "rss_pages": rss_pages if rss_pages is not None and rss_pages >= 0 else None,
    }


def parse_status(text: str) -> dict:
    out: dict = {"uid": None, "rss_kb": None, "state": None, "name": None}
    for line in text.splitlines():
        if line.startswith("Uid:"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    uid = int(parts[1])
                except ValueError:
                    continue
                if uid >= 0:
                    out["uid"] = uid
        elif line.startswith("VmRSS:"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    rss_kb = int(parts[1])
                except ValueError:
                    continue
                if rss_kb >= 0:
                    out["rss_kb"] = rss_kb
        elif line.startswith("State:"):
            parts = line.split()
            if len(parts) >= 2 and parts[1]:
                out["state"] = parts[1][0]
        elif line.startswith("Name:"):
            out["name"] = line.split(":", 1)[1].strip()
    return out


def group_score(group: dict, total_bytes: int) -> float:
    cpu = group["cpu"] if group["cpu"] is not None else 0.0
    mem = group["memoryBytes"]
    mem_pct = (100.0 * mem / total_bytes) if total_bytes else 0.0
    return cpu * 2.0 + mem_pct


def rank_groups(groups: list[dict], total_bytes: int, limit: int = MAX_GROUPS) -> list[dict]:
    ordered = sorted(
        groups,
        key=lambda g: (-group_score(g, total_bytes), g["key"]),
    )
    trimmed = []
    for g in ordered[:limit]:
        trimmed.append(
            {
                "key": g["key"],
                "name": g["name"],
                "count": g["count"],
                "cpu": g["cpu"],
                "memoryBytes": g["memoryBytes"],
                "category": g["category"],
            }
        )
    return trimmed


def empty_sample(timestamp: int, errors: list[str] | None = None) -> dict:
    return {
        "version": VERSION,
        "timestamp": timestamp,
        "interval": 0.0,
        "cpu": None,
        "memory": {"usedBytes": 0, "totalBytes": 0, "percent": None},
        "network": {
            "rxBytesPerSec": None,
            "txBytesPerSec": None,
            "interfaces": [],
        },
        "processes": [],
        "processCount": 0,
        "uptimeSeconds": 0,
        "errors": list(errors or []),
    }


def net_rates(
    prev: dict[str, tuple[int, int]] | None,
    current: dict[str, tuple[int, int]],
    elapsed: float,
) -> tuple[float | None, float | None]:
    if prev is None:
        return None, None
    if elapsed <= 0:
        return None, None
    rx_sum = 0.0
    tx_sum = 0.0
    for name, (rx, tx) in current.items():
        old = prev.get(name)
        if old is None:
            continue
        prev_rx, prev_tx = old
        if rx >= prev_rx:
            rx_sum += (rx - prev_rx) / elapsed
        if tx >= prev_tx:
            tx_sum += (tx - prev_tx) / elapsed
    return max(0.0, rx_sum), max(0.0, tx_sum)


class Collector:
    """Stateful sampler. Call sample() repeatedly to obtain deltas."""

    def __init__(
        self,
        proc_root: str | os.PathLike = "/proc",
        uid: int | None = None,
        self_pid: int | None = None,
        time_fn=None,
        monotonic_fn=None,
        page_size_bytes: int | None = None,
    ) -> None:
        self.proc_root = Path(proc_root)
        self.uid = int(os.getuid() if uid is None else uid)
        self.self_pid = int(os.getpid() if self_pid is None else self_pid)
        self._time = time_fn or time.time
        self._monotonic = monotonic_fn or time.monotonic
        self.page_size = int(page_size() if page_size_bytes is None else page_size_bytes)
        if self.page_size <= 0:
            self.page_size = PAGE_SIZE_FALLBACK
        self._prev_mono: float | None = None
        self._prev_cpu: tuple[int, int] | None = None
        self._prev_net: dict[str, tuple[int, int]] | None = None
        self._prev_procs: dict[tuple[int, int], int] | None = None

    def sample(self) -> dict:
        errors: list[str] = []
        now = self._time()
        try:
            timestamp = int(now)
        except (TypeError, ValueError, OverflowError):
            timestamp = 0
        mono = self._monotonic()
        try:
            mono = float(mono)
        except (TypeError, ValueError):
            mono = 0.0
        if self._prev_mono is None:
            elapsed = 0.0
        else:
            elapsed = mono - self._prev_mono
            if elapsed < 0:
                elapsed = 0.0
        interval = elapsed if self._prev_mono is not None else 0.0

        cpu, cpu_delta = self._sample_cpu(errors)
        memory = self._sample_memory(errors)
        net_cur, net_names, net_ok = self._sample_net(errors)
        if net_ok:
            rx, tx = net_rates(self._prev_net, net_cur, elapsed)
            self._prev_net = net_cur
        else:
            rx, tx = None, None
            self._prev_net = None
        uptime = self._sample_uptime(errors)
        processes, process_count, next_procs = self._sample_processes(
            errors, cpu_delta
        )
        ranked = rank_groups(processes, memory["totalBytes"])

        self._prev_mono = mono
        self._prev_procs = next_procs

        return {
            "version": VERSION,
            "timestamp": timestamp,
            "interval": interval,
            "cpu": cpu,
            "memory": memory,
            "network": {
                "rxBytesPerSec": rx,
                "txBytesPerSec": tx,
                "interfaces": net_names,
            },
            "processes": ranked,
            "processCount": process_count,
            "uptimeSeconds": uptime if uptime is not None else 0,
            "errors": errors,
        }

    def _sample_cpu(self, errors: list[str]) -> tuple[float | None, int | None]:
        text = read_text(self.proc_root / "stat")
        parsed = parse_proc_stat_cpu(text) if text is not None else None
        if parsed is None:
            add_error(errors, "cpu counters unreadable")
            self._prev_cpu = None
            return None, None
        total, idle = parsed
        cpu = None
        delta = None
        if self._prev_cpu is not None:
            cpu = cpu_percent(self._prev_cpu[0], self._prev_cpu[1], total, idle)
            if cpu is None:
                delta = None
            else:
                delta = total - self._prev_cpu[0]
                if delta <= 0:
                    delta = None
                    cpu = None
        self._prev_cpu = (total, idle)
        return cpu, delta

    def _sample_memory(self, errors: list[str]) -> dict:
        text = read_text(self.proc_root / "meminfo")
        parsed = parse_meminfo(text) if text is not None else None
        if parsed is None:
            add_error(errors, "memory counters unreadable")
            return {"usedBytes": 0, "totalBytes": 0, "percent": None}
        used, total, percent = parsed
        return {"usedBytes": used, "totalBytes": total, "percent": percent}

    def _sample_net(
        self, errors: list[str]
    ) -> tuple[dict[str, tuple[int, int]], list[str], bool]:
        text = read_text(self.proc_root / "net" / "dev")
        if text is None:
            add_error(errors, "network counters unreadable")
            return {}, [], False
        current = parse_netdev(text)
        names = sorted(current.keys())
        return current, names, True

    def _sample_uptime(self, errors: list[str]) -> float | None:
        text = read_text(self.proc_root / "uptime")
        value = parse_uptime(text) if text is not None else None
        if value is None:
            add_error(errors, "uptime unreadable")
        return value

    def _dir_uid(self, path: Path) -> int | None:
        try:
            return int(path.stat().st_uid)
        except OSError:
            return None

    def _sample_processes(
        self, errors: list[str], machine_delta: int | None
    ) -> tuple[list[dict], int, dict[tuple[int, int], int]]:
        groups: dict[str, dict] = {}
        next_procs: dict[tuple[int, int], int] = {}
        count = 0
        scanned = 0
        truncated = False
        try:
            entries = os.scandir(self.proc_root)
        except OSError:
            add_error(errors, "process scan incomplete")
            return [], 0, {}

        with entries:
            for entry in entries:
                name = entry.name
                if not name.isdigit():
                    continue
                if len(name) > 1 and name.startswith("0"):
                    continue
                scanned += 1
                if scanned > MAX_SCAN_PIDS:
                    truncated = True
                    break
                try:
                    pid = int(name)
                except ValueError:
                    continue
                if pid == self.self_pid:
                    continue
                rec = self._read_process(entry)
                if rec is None:
                    continue
                ident = (rec["pid"], rec["starttime"])
                next_procs[ident] = rec["ticks"]
                cpu = None
                if (
                    machine_delta is not None
                    and machine_delta > 0
                    and self._prev_procs is not None
                    and ident in self._prev_procs
                ):
                    dticks = rec["ticks"] - self._prev_procs[ident]
                    if dticks >= 0:
                        cpu = clamp(100.0 * dticks / machine_delta, 0.0, 100.0)
                count += 1
                key = _norm_key(rec["comm"])
                group = groups.get(key)
                if group is None:
                    group = {
                        "key": key,
                        "name": sanitize_name(rec["comm"]),
                        "count": 0,
                        "cpu": None,
                        "memoryBytes": 0,
                        "category": categorize(rec["comm"]),
                    }
                    groups[key] = group
                group["count"] += 1
                group["memoryBytes"] += rec["rss_bytes"]
                if cpu is not None:
                    group["cpu"] = (group["cpu"] or 0.0) + cpu

        if truncated:
            add_error(errors, "process scan truncated")
        return list(groups.values()), count, next_procs

    def _read_process(self, entry: os.DirEntry) -> dict | None:
        pid_path = Path(entry.path)
        try:
            if not entry.is_dir(follow_symlinks=False):
                return None
        except OSError:
            return None

        stat_text = read_text(pid_path / "stat")
        if stat_text is None:
            return None
        parsed = parse_pid_stat(stat_text)
        if parsed is None:
            return None
        state = parsed["state"]
        if state in ("Z", "X"):
            return None

        status_text = read_text(pid_path / "status")
        status = parse_status(status_text) if status_text else {}
        uid = status.get("uid") if status else None
        if uid is None:
            uid = self._dir_uid(pid_path)
        if uid is None or uid != self.uid:
            return None
        if status.get("state") in ("Z", "X"):
            return None

        comm_text = read_text(pid_path / "comm")
        comm = None
        if comm_text is not None:
            comm = comm_text.splitlines()[0] if comm_text else ""
        if not comm and status.get("name"):
            comm = status["name"]
        if not comm:
            comm = parsed["comm"]

        rss_bytes = 0
        if status.get("rss_kb") is not None:
            rss_bytes = int(status["rss_kb"]) * 1024
        elif parsed["rss_pages"] is not None:
            rss_bytes = int(parsed["rss_pages"]) * self.page_size
        if rss_bytes < 0:
            rss_bytes = 0

        return {
            "pid": parsed["pid"],
            "starttime": parsed["starttime"],
            "ticks": parsed["ticks"],
            "comm": comm,
            "rss_bytes": rss_bytes,
        }


def collect_once(
    proc_root: str | os.PathLike = "/proc",
    uid: int | None = None,
    self_pid: int | None = None,
) -> dict:
    return Collector(proc_root=proc_root, uid=uid, self_pid=self_pid).sample()


def emit_sample(sample: dict, file=None) -> None:
    file = sys.stdout if file is None else file
    line = json.dumps(sample, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    file.write(line + "\n")
    file.flush()


def interval_type(text: str) -> float:
    try:
        value = float(text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "interval must be a number between 1 and 60"
        ) from exc
    if value != value or value < MIN_INTERVAL or value > MAX_INTERVAL:
        raise argparse.ArgumentTypeError("interval must be between 1 and 60")
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Emit read-only Linux telemetry as NDJSON."
    )
    parser.add_argument(
        "--interval",
        type=interval_type,
        default=DEFAULT_INTERVAL,
        help="seconds between samples in stream mode (1-60, default 2)",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="emit a single sample immediately and exit",
    )
    parser.add_argument(
        "--proc-root",
        default="/proc",
        help="procfs root (default /proc; for tests)",
    )
    return parser


def stdin_watch_fd(stdin=None) -> int | None:
    stream = sys.stdin if stdin is None else stdin
    try:
        if stream is None or getattr(stream, "closed", False):
            return None
        fd = stream.fileno()
    except (AttributeError, OSError, ValueError):
        return None
    try:
        mode = os.fstat(fd).st_mode
    except OSError:
        return None
    if stat.S_ISFIFO(mode) or stat.S_ISSOCK(mode):
        return fd
    try:
        if os.isatty(fd):
            return fd
    except OSError:
        return None
    return None


def wait_for_stop(seconds: float, state: RunState, stdin_fd: int | None) -> bool:
    """Sleep up to seconds. True means the caller should stop streaming."""
    if state.stop:
        return True
    deadline = time.monotonic() + max(0, seconds)
    first_poll = True
    while not state.stop:
        remaining = deadline - time.monotonic()
        if remaining <= 0 and not first_poll:
            return False
        first_poll = False
        chunk = max(0, min(remaining, 0.5))
        if stdin_fd is None:
            if chunk == 0:
                return False
            try:
                time.sleep(chunk)
            except InterruptedError:
                continue
            continue
        try:
            ready, _, _ = select.select([stdin_fd], [], [], chunk)
        except InterruptedError:
            continue
        except (OSError, ValueError):
            try:
                time.sleep(chunk)
            except InterruptedError:
                continue
            continue
        if not ready:
            continue
        try:
            data = os.read(stdin_fd, 4096)
        except OSError:
            state.stop = True
            return True
        if not data:
            state.stop = True
            return True
    return True


def run_stream(collector: Collector, interval: float) -> int:
    state = RunState()

    def _request_stop(signum, frame) -> None:
        state.stop = True
        raise StopStreaming()

    previous = {}
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        try:
            previous[sig] = signal.signal(sig, _request_stop)
        except (OSError, ValueError):
            pass
    stdin_fd = stdin_watch_fd()
    try:
        while not state.stop:
            started = time.monotonic()
            try:
                emit_sample(collector.sample())
            except BrokenPipeError:
                return 0
            except OSError as exc:
                if getattr(exc, "errno", None) == errno.EPIPE:
                    return 0
                try:
                    emit_sample(
                        empty_sample(
                            int(collector._time()),
                            ["sample failed"],
                        )
                    )
                except (BrokenPipeError, OSError):
                    return 0
                if wait_for_stop(max(interval, MIN_INTERVAL), state, stdin_fd):
                    break
                continue
            except Exception:
                try:
                    emit_sample(
                        empty_sample(int(collector._time()), ["sample failed"])
                    )
                except (BrokenPipeError, OSError):
                    return 0
                if wait_for_stop(max(interval, MIN_INTERVAL), state, stdin_fd):
                    break
                continue
            if state.stop:
                break
            spent = time.monotonic() - started
            # An unusually slow scan must still yield to the desktop. Do not
            # turn an interval overrun into continuous procfs scanning.
            remaining = interval if spent >= interval else interval - spent
            if wait_for_stop(remaining, state, stdin_fd):
                break
        return 0
    except (KeyboardInterrupt, StopStreaming):
        return 0
    except BrokenPipeError:
        return 0
    finally:
        for sig, handler in previous.items():
            try:
                signal.signal(sig, handler)
            except (OSError, ValueError):
                pass


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    collector = Collector(proc_root=args.proc_root)
    if args.once:
        try:
            emit_sample(collector.sample())
        except BrokenPipeError:
            return 0
        except OSError as exc:
            if getattr(exc, "errno", None) == errno.EPIPE:
                return 0
            raise
        return 0
    return run_stream(collector, args.interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except Exception:
            pass
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(0)
