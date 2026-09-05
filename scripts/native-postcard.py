#!/usr/bin/env python3
"""Opt-in native keyboard/export check, using clearly labeled synthetic data.

Requires wtype. Opens Terrarium, saves two demo postcards in Pictures/Terrarium,
checks their PNG headers, removes only those test outputs, and restores settings.
Run while the desktop is available for keyboard-driven testing.
"""
import json
from pathlib import Path
import struct
import subprocess
import time

PLUGIN = "io.github.lostandadrift.terrarium"


def command(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=5).stdout.strip()


def call(*args):
    result = command("omarchy-shell", *args)
    if result in ("Target not found.", "Function not found."):
        raise RuntimeError(result)
    return result


def state():
    return json.loads(call("terrarium", "state"))


def until(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = state()
        if predicate(value):
            return value
        time.sleep(.15)
    raise AssertionError("Native postcard state did not settle")


def key(name, control=False):
    current = state()
    assert current["opened"] and current["demo"] and not current["locked"], "Synthetic Terrarium panel must own the test interaction"
    command("wtype", *(["-M", "ctrl", "-k", name, "-m", "ctrl"] if control else ["-k", name]))


def check_png(path):
    with path.open("rb") as handle:
        header = handle.read(24)
        assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR"
        dimensions = struct.unpack(">II", header[16:24])
        assert abs(dimensions[0]-1800) <= 1 and abs(dimensions[1]-1100) <= 1, "Export dimensions changed with display scaling"
    assert path.stat().st_size > 10000, "Saved postcard is unexpectedly small"
    return dimensions


def run():
    original = state()
    created = []
    dimensions = []
    started = time.time()
    try:
        if original["ambient"]:
            call("terrarium", "ambient")
        call("shell", "summon", PLUGIN, "{}")
        if not state()["demo"]:
            call("terrarium", "demo")
        until(lambda s: s["opened"] and s["demo"] and not s["collectorRunning"])
        call("terrarium", "section", "options")
        key("s", control=True)
        until(lambda s: s["section"] == "postcard" and s["postcardReady"])
        before = state()["samples"]
        # The preview stays frozen while its independent synthetic model updates.
        until(lambda s: s["samples"] > before)
        for _ in range(2):
            key("s", control=True)
            saved = until(lambda s: not s["exportBusy"] and bool(s["exportPath"]))
            path = Path(saved["exportPath"])
            assert path.name.startswith("terrarium-") and path.suffix == ".png" and path.parent.name == "Terrarium"
            assert path.stat().st_ctime >= started-2 and str(path) != original.get("exportPath", "")
            assert path not in [item[0] for item in created], "Repeated save overwrote its previous image"
            identity = path.stat()
            created.append((path, identity.st_dev, identity.st_ino))
            dimensions.append(check_png(path))
            if len(created) == 1:
                # Leave and re-enter to clear completed status before the next save.
                key("Escape")
                until(lambda s: s["section"] == "options")
                key("s", control=True)
                until(lambda s: s["section"] == "postcard" and s["postcardReady"] and not s["exportPath"])
        key("Escape")
        until(lambda s: s["section"] == "options" and not s["exportBusy"])
        print(json.dumps({"passed": True, "exports": 2, "pixelDimensions": dimensions,
                          "checks": ["real keyboard preview and save", "demo without live collection", "distinct output paths",
                                     "native PNG output", "return to previous section"]}, indent=2))
    finally:
        # These exact files were created by the above synthetic export operations.
        for path, device, inode in created:
            try:
                current = path.lstat()
                if current.st_dev == device and current.st_ino == inode and not path.is_symlink():
                    path.unlink()
            except FileNotFoundError:
                pass
        current = state()
        if current["section"] == "postcard":
            call("terrarium", "section", "garden")
        until(lambda s: not s["exportBusy"])
        if state()["demo"] != original["demo"]:
            call("terrarium", "demo")
        if state()["ambient"] != original["ambient"]:
            call("terrarium", "ambient")
        call("terrarium", "section", original["section"] if original["section"] != "postcard" else "garden")
        if original["opened"]:
            call("shell", "summon", PLUGIN, "{}")
        else:
            call("shell", "hide", PLUGIN)


if __name__ == "__main__":
    run()
