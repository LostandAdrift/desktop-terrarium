#!/usr/bin/env python3
"""Opt-in native placement check; temporarily pins Terrarium, then restores it.

Checks real compositor layer geometry on every connected output. It does not
disconnect outputs, capture the desktop, or alter other shell layers.
"""
import json
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


def until(predicate, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = state()
        if predicate(result):
            return result
        time.sleep(.2)
    raise AssertionError("Terrarium did not reach the expected placement state")


def layers():
    data = json.loads(command("hyprctl", "-j", "layers"))
    return [(name, layer) for name, monitor in data.items()
            for entries in monitor.get("levels", {}).values() for layer in entries
            if layer.get("namespace") == "desktop-terrarium"]


def check_geometry(monitor, layer, corner, size):
    width, height = monitor["width"], monitor["height"]
    if monitor["transform"] % 2:
        width, height = height, width
    width, height = width / monitor["scale"], height / monitor["scale"]
    margin = min(36, int(min(width, height) // 8))
    target = min({"small": 440, "medium": 600, "large": 760}[size], width-2*margin, (height-2*margin)*900/550)
    assert abs(layer["w"]-target) <= 2, "Pinned width did not use logical dimensions"
    assert abs(layer["h"]-target*550/900) <= 2, "Pinned aspect ratio changed"
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    expected_x = monitor["x"] + (left+margin if corner.endswith("left") else width-right-margin-layer["w"])
    expected_y = monitor["y"] + (top+margin if corner.startswith("top") else height-bottom-margin-layer["h"])
    assert abs(layer["x"]-expected_x) <= 2, "Pinned horizontal edge did not respect its margin"
    assert abs(layer["y"]-expected_y) <= 2, "Pinned vertical edge did not respect reserved shell space"


def run():
    original = state()
    monitors = {m["name"]: m for m in json.loads(command("hyprctl", "-j", "monitors"))}
    displays = original["availableDisplays"]
    assert displays and all(name in monitors for name in displays), "Outputs changed before the test"
    cases = 0
    try:
        if not original["reducedMotion"]:
            call("terrarium", "motion")
        if not original["ambient"]:
            call("terrarium", "ambient")
        call("shell", "hide", PLUGIN)
        initial = until(lambda s: s["ambientVisible"] and s["collectorRunning"] and not s["stale"])
        pid = initial["collectorPid"]
        for display in displays:
            call("terrarium", "placement", "ambientDisplay", display)
            for corner in ("top-left", "top-right", "bottom-left", "bottom-right"):
                call("terrarium", "placement", "ambientCorner", corner)
                for size in ("small", "medium", "large"):
                    call("terrarium", "placement", "ambientSize", size)
                    until(lambda s: s["ambientActualDisplay"] == display and s["ambientCorner"] == corner and s["ambientSize"] == size)
                    deadline = time.monotonic() + 3
                    while True:
                        actual = layers()
                        try:
                            assert len(actual) == 1 and actual[0][0] == display, "Expected exactly one pinned layer on the selected output"
                            check_geometry(monitors[display], actual[0][1], corner, size)
                            break
                        except AssertionError:
                            if time.monotonic() >= deadline:
                                raise
                            time.sleep(.1)
                    values = json.loads(call("terrarium", "allStates"))
                    assert sum(s["ambientVisible"] for s in values) == 1
                    assert all(s["collectorPid"] == pid and s["watcherCount"] == 1 for s in values), "Moving the garden duplicated or restarted observation"
                    cases += 1
        missing = "terrarium-test-disconnected-output"
        assert missing not in displays
        call("terrarium", "placement", "ambientDisplay", missing)
        until(lambda s: s["ambientFallback"] and s["ambientDisplay"] == missing and s["ambientActualDisplay"] == displays[0])
        call("terrarium", "placement", "ambientDisplay", displays[-1])
        until(lambda s: not s["ambientFallback"] and s["ambientActualDisplay"] == displays[-1])
        assert state()["collectorPid"] == pid
        print(json.dumps({"passed": True, "geometryCases": cases, "displays": len(displays),
                          "checks": ["all corners and sizes", "logical scaling and bar reservations", "one layer and observer",
                                     "missing output preference retained with fallback", "connected selection restored"]}, indent=2))
    finally:
        for key in ("ambientDisplay", "ambientCorner", "ambientSize"):
            call("terrarium", "placement", key, original[key])
        current = state()
        if current["ambient"] != original["ambient"]:
            call("terrarium", "ambient")
        if current["reducedMotion"] != original["reducedMotion"]:
            call("terrarium", "motion")
        call("terrarium", "section", original["section"])
        if original["opened"]:
            call("shell", "summon", PLUGIN, "{}")
        else:
            call("shell", "hide", PLUGIN)
        if not original["opened"] and not original["ambient"]:
            until(lambda s: not s["collectorRunning"] and s["watcherCount"] == 0)


if __name__ == "__main__":
    run()
