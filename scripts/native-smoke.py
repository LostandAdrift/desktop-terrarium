#!/usr/bin/env python3
"""Opt-in integration test. Opens the installed plugin on the real desktop.

Run manually only after installing the development plugin. It does not capture
the screen or modify other plugins. It restores the original preferences.
"""
import argparse
import json
import os
import signal
import subprocess
import time

PLUGIN = 'io.github.lostandadrift.terrarium'


def call(*args):
    out = subprocess.run(['omarchy-shell', *args], capture_output=True, text=True, check=True, timeout=5).stdout.strip()
    if out in ('Target not found.', 'Function not found.'):
        raise RuntimeError(out)
    return out


def state():
    return json.loads(call('terrarium', 'state'))


def until(predicate, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = state()
        if predicate(value):
            return value
        time.sleep(0.25)
    raise AssertionError('Runtime condition timed out: ' + json.dumps(state()))


def run(fault=False):
    original = state()
    checks = []
    try:
        if original['ambient']:
            call('terrarium', 'ambient')
        call('shell', 'summon', PLUGIN, '{}')
        if state()['demo']:
            call('terrarium', 'demo')
        live = until(lambda s: s['opened'] and s['collectorRunning'] and s['samples'] >= 2 and not s['stale'])
        assert live['residents'] > 0
        checks.append('live telemetry arrives')
        call('terrarium', 'demo')
        until(lambda s: s['demo'] and not s['collectorRunning'] and s['residents'] > 0)
        checks.append('demo is distinct and stops real collection')
        call('terrarium', 'section', 'guide')
        assert state()['section'] == 'guide'
        call('terrarium', 'section', 'garden')
        call('terrarium', 'motion')
        assert state()['reducedMotion'] != original['reducedMotion']
        call('terrarium', 'motion')
        checks.append('view actions and persistent motion preference work')
        call('terrarium', 'demo')
        live = until(lambda s: not s['demo'] and s['collectorRunning'])
        if fault:
            pid = live['collectorPid']
            assert isinstance(pid, int) and pid > 1
            # Only the observer PID returned by this plugin's own IPC state.
            os.kill(pid, signal.SIGTERM)
            until(lambda s: s['stale'] and not s['collectorRunning'])
            call('terrarium', 'retry')
            until(lambda s: s['collectorRunning'] and not s['stale'])
            checks.append('observer termination has a visible recoverable state')
        call('shell', 'hide', PLUGIN)
        until(lambda s: not s['opened'] and not s['collectorRunning'])
        all_states = json.loads(call('terrarium', 'allStates'))
        assert not any(s['collectorRunning'] for s in all_states)
        checks.append('all monitors stop collection when closed')
        call('shell', 'summon', PLUGIN, '{}')
        until(lambda s: s['opened'] and s['collectorRunning'] and not s['stale'])
        checks.append('reopening restarts observation')
        print(json.dumps({'passed': len(checks), 'checks': checks}, indent=2))
    finally:
        try:
            current = state()
            if current['demo'] != original['demo']:
                call('terrarium', 'demo')
            if current['reducedMotion'] != original['reducedMotion']:
                call('terrarium', 'motion')
            if current['ambient'] != original['ambient']:
                call('terrarium', 'ambient')
            if not original['opened']:
                call('shell', 'hide', PLUGIN)
        except (subprocess.SubprocessError, ValueError, RuntimeError):
            pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fault', action='store_true', help='also terminate the plugin-owned observer and verify recovery')
    run(parser.parse_args().fault)
