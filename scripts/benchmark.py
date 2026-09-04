#!/usr/bin/env python3
"""Opt-in live resource measurement for the installed plugin.

Uses synthetic demo data while measuring the existing Omarchy shell and the
plugin-owned observer. No application content or process names are saved.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

PLUGIN = 'io.github.lostandadrift.terrarium'
HZ = os.sysconf('SC_CLK_TCK')
PAGE = os.sysconf('SC_PAGE_SIZE')


def call(*args):
    return subprocess.check_output(['omarchy-shell', *args], text=True, timeout=5).strip()


def state():
    return json.loads(call('terrarium', 'state'))


def counter(pid):
    try:
        data = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return {'ticks': int(data[11]) + int(data[12]), 'rss': int(data[21]) * PAGE}
    except (OSError, ValueError, IndexError):
        return None


def measure(pids, seconds):
    before = {pid: counter(pid) for pid in pids}
    started = time.monotonic()
    peak = {pid: (value['rss'] if value else 0) for pid, value in before.items()}
    while time.monotonic() - started < seconds:
        time.sleep(0.5)
        for pid in pids:
            value = counter(pid)
            if value:
                peak[pid] = max(peak[pid], value['rss'])
    elapsed = time.monotonic() - started
    result = []
    for pid in pids:
        after = counter(pid)
        if after and before[pid]:
            result.append({'cpuPercentOfOneCore': round(100 * (after['ticks'] - before[pid]['ticks']) / HZ / elapsed, 2),
                           'rssMiB': round(after['rss'] / 1048576, 1), 'peakRssMiB': round(peak[pid] / 1048576, 1)})
    return result


def run(seconds):
    shell_pids = [int(p) for p in subprocess.check_output(['pgrep', '-u', str(os.getuid()), '-x', 'quickshell'], text=True).split()]
    original = state()
    results = {'secondsPerPhase': seconds, 'logicalCpus': os.cpu_count(), 'shellProcesses': len(shell_pids), 'phases': {}}
    try:
        if original['ambient']:
            call('terrarium', 'ambient')
        call('shell', 'hide', PLUGIN)
        time.sleep(1)
        results['phases']['closed'] = measure(shell_pids, seconds)
        call('shell', 'summon', PLUGIN, '{}')
        if not state()['demo']:
            call('terrarium', 'demo')
        if state()['reducedMotion']:
            call('terrarium', 'motion')
        time.sleep(1)
        results['phases']['animatedDemo'] = measure(shell_pids, seconds)
        call('terrarium', 'motion')
        time.sleep(1)
        results['phases']['stillDemo'] = measure(shell_pids, seconds)
        call('terrarium', 'demo')
        time.sleep(3)
        observer = state().get('collectorPid')
        results['phases']['liveStill'] = measure(shell_pids + ([observer] if observer else []), seconds)
        return results
    finally:
        current = state()
        if current['demo'] != original['demo']:
            call('terrarium', 'demo')
        if current['reducedMotion'] != original['reducedMotion']:
            call('terrarium', 'motion')
        if current['ambient'] != original['ambient']:
            call('terrarium', 'ambient')
        if not original['opened']:
            call('shell', 'hide', PLUGIN)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=15)
    args = parser.parse_args()
    if not 5 <= args.seconds <= 60:
        parser.error('--seconds must be between 5 and 60')
    print(json.dumps(run(args.seconds), indent=2))
