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


def until_all_stopped(timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        values = json.loads(call('terrarium', 'allStates'))
        if values and not any(s['collectorRunning'] or s['opened'] for s in values):
            return
        time.sleep(0.25)
    raise AssertionError('A monitor retained an observer after dismissal')


def run(fault=False, stress=False, stall=False):
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
        until_all_stopped()
        checks.append('all monitors stop collection when closed')
        call('shell', 'summon', PLUGIN, '{}')
        previous_samples = state()['samples']
        until(lambda s: s['opened'] and s['collectorRunning'] and not s['stale'] and s['samples'] > previous_samples)
        checks.append('reopening restarts observation')
        if stall:
            # Deliberately hold only the owned observer past the shutdown
            # watchdog, then let the queued SIGTERM complete. No second retry
            # should be needed and no replacement may overlap the old child.
            held_pid = state()['collectorPid']
            assert isinstance(held_pid, int) and held_pid > 1
            os.kill(held_pid, signal.SIGSTOP)
            try:
                call('terrarium', 'retry')
                time.sleep(10)
                held = state()
                assert held['collectorPid'] == held_pid and held['stale'], json.dumps(held)
            finally:
                try:
                    os.kill(held_pid, signal.SIGCONT)
                except ProcessLookupError:
                    pass
            prior = state()['liveSamples']
            until(lambda s: s['collectorRunning'] and s['collectorPid'] != held_pid and not s['stale'] and s['liveSamples'] > prior)
            checks.append('a stalled intentional shutdown resumes without a second retry or overlapping observer')
        if stress:
            # Immediate pairs exercise shutdown/start races without assuming
            # a subprocess has exited by the time hide() returns.
            for _ in range(12):
                call('shell', 'hide', PLUGIN)
                call('shell', 'summon', PLUGIN, '{}')
            prior = state()['liveSamples']
            until(lambda s: s['collectorRunning'] and not s['stale'] and s['liveSamples'] > prior)
            for _ in range(8):
                call('terrarium', 'retry')
            prior = state()['liveSamples']
            until(lambda s: s['collectorRunning'] and not s['stale'] and s['liveSamples'] > prior)
            checks.append('rapid close/reopen and repeated retry recover')
            call('terrarium', 'ambient')
            call('shell', 'hide', PLUGIN)
            until(lambda s: s['ambient'] and s['collectorRunning'])
            states = json.loads(call('terrarium', 'allStates'))
            assert sum(s['ambientVisible'] for s in states) == 1
            assert len({s['collectorPid'] for s in states}) == 1
            assert len({s['liveSamples'] for s in states}) == 1
            assert all(s['watcherCount'] == 1 for s in states)
            call('shell', 'summon', PLUGIN, '{}')
            prior = state()['liveSamples']
            until(lambda s: s['liveSamples'] > prior)
            states = json.loads(call('terrarium', 'allStates'))
            assert len({s['collectorPid'] for s in states}) == 1
            assert len({s['liveSamples'] for s in states}) == 1
            call('terrarium', 'ambient')
            call('shell', 'hide', PLUGIN)
            until_all_stopped()
            checks.append('pinned mode shares one observer across all displays and stops cleanly')
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
            elif not current['opened']:
                call('shell', 'summon', PLUGIN, '{}')
        except (subprocess.SubprocessError, ValueError, RuntimeError):
            pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fault', action='store_true', help='also terminate the plugin-owned observer and verify recovery')
    parser.add_argument('--stress', action='store_true', help='also exercise rapid lifecycle transitions and pinned mode')
    parser.add_argument('--stall', action='store_true', help='hold only the owned observer for 10 seconds to test delayed shutdown')
    args = parser.parse_args()
    run(args.fault, args.stress, args.stall)
