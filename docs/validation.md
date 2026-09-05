# Validation record

This is a record of checks performed on September 4, 2026, not a guarantee for every desktop configuration.

## Environments

- Native desktop: Omarchy 4.0.2, Qt 6.11.2, Python 3.14, three displays with mixed orientation and scaling, sixteen logical CPUs.
- Continuous integration: a fresh Arch Linux container on GitHub Actions, with the QtQuick software renderer and no desktop session.
- Standalone render checks: 1120 × 720, 720 × 620, 960 × 480, and 640 × 480. The layout switches to its compact form when width is below 850 or height is below 640.

## Automated and native checks

- Forty-seven Python tests cover procfs parsing, memory and CPU calculations, counter resets, interface changes, process disappearance and PID reuse, UID filtering, bounded output, privacy, argument validation, and stream termination. Cancellation tests interrupt a deliberately slow sample and verify that overrunning samples leave a rest interval.
- Seven JavaScript tests cover normalization, hostile or malformed names, stable resident positions, departure grace, bounded history, suspension gaps, formatting, and repeatable demo activity.
- Seventeen rendered QtQuick test cases cover navigation, action signals, resident selection, empty/error states, compact layouts and palettes, keyboard scrolling, Tab activation, edge tooltips, and a full resident list on a short panel. QtTest reports nineteen passes including its setup and cleanup cases. Unexpected QML warnings fail the tests.
- A windowless Quickshell integration test uses the production shared store and observer. Two watchers share one PID; a deliberate ten-second shutdown stall retains ownership, recovers without a second retry, and leaves no observer after the final watcher closes. This regression also runs in CI.
- Eight native smoke checks cover live readings, demo isolation, settings, observer termination and retry, close/reopen, stopping on all monitors, rapid transitions, and one shared observer in pinned mode.
- Installation checks passed with an active observer: disable stopped the child and unloaded IPC; re-enable resumed observations; removal stopped the child and removed the installed copy; a fresh clone from the public repository started and closed correctly with a clean Git checkout.
- Native synthetic-demo rendering was inspected in the actual Omarchy panel. The shell log contained no Terrarium warnings after the lifecycle checks.

Release candidate `52bbbea` passed [GitHub Actions](https://github.com/LostandAdrift/desktop-terrarium/actions/runs/33931788731), including the delayed-shutdown regression. The same commit passed all eight native smoke checks after a standard plugin update from GitHub, with a clean installed checkout and no Terrarium warnings in the shell log. Each release is made only after its source checks pass; the workflow is visible in the repository's **Actions** tab. Run instructions are in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Resource measurements

These measurements use twenty-second windows on one running desktop at commit `3a573e4`, before the final layout refinements. Shell values include every other active Omarchy plugin. They are useful for comparing phases in this run; they are not Terrarium's isolated total CPU or memory use.

| Phase | Entire shell CPU, % of one core | Entire shell RSS, MiB | Observer CPU, % of one core | Observer RSS, MiB |
| --- | ---: | ---: | ---: | ---: |
| Terrarium closed | 33.63 | 804.4 | Not running | Not running |
| Animated demo | 39.38 | 834.5 | Not running | Not running |
| Demo with motion paused | 34.33 | 836.9 | Not running | Not running |
| Live with motion paused | 35.08 | 838.8 | 1.15 | 19.0 |

The animated phase added about 5.75 percentage points of one CPU core over the closed baseline in this run. Pausing motion returned shell CPU close to that baseline. RSS may retain allocations after a panel closes. A second, shorter run showed similar CPU differences; results vary with hardware, active applications, display scale, and other plugins.

Use `python3 scripts/benchmark.py --seconds 20` to repeat the measurement. It temporarily opens the panel and restores its original preferences.

## Limits

Native lifecycle coverage is currently one Omarchy installation with three monitors. CI exercises the portable view and telemetry model, not a compositor. There is no claim of validation on every Omarchy theme, arbitrary fractional scale, or older Quickshell release. The smallest inspected content area is 640 × 480.

Summed process RSS can double-count shared pages. Network interfaces can count the same VPN traffic at more than one layer. A top process group disappearing is not proof that its work completed. These limits are also documented in the application and [telemetry specification](telemetry.md).
