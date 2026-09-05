# Contributing

Desktop Terrarium is a native Omarchy Quattro plugin. Please open an issue describing the behavior you want to change before a large contribution. Small fixes with a clear reproduction are welcome.

## Local checks

On Omarchy, run:

```sh
bash scripts/check.sh
```

The Python tests use synthetic procfs trees. The JavaScript tests exercise state transitions, ordering, missing data, and bounded history. QtQuick tests create the real view offscreen and exercise keyboard interactions, compact layouts, and error states. No test requires an account or a network connection.

The GitHub workflow runs those tests in a fresh Arch container. It cannot validate your actual Omarchy shell, compositor, or monitor setup; native integration tests remain a separate step.

When Quickshell is installed, `bash scripts/check-store.sh` also tests the real observer lifecycle without opening any window. It copies the production store and collector into an isolated temporary configuration, pauses only that configuration's observer past the shutdown watchdog, then checks automatic recovery and final cleanup. It never controls the existing Omarchy shell.

## Native integration

After installing a development version, these commands temporarily open the plugin on your desktop:

```sh
python3 scripts/native-smoke.py --fault --stress
python3 scripts/benchmark.py --seconds 15
```

The fault test terminates only the plugin's own observer process and checks recovery. Both scripts restore the original preferences and close the popup if it began closed. Run them when you are comfortable with the popup opening.

Omarchy watches installed plugin files. Some changes to already-cached QML components can require `omarchy restart shell` during development. Never edit the packaged shell under `/usr/share/omarchy`.

## Synthetic previews

Render the real view without opening a desktop window:

```sh
bash scripts/render-previews.sh /tmp/terrarium-previews
```

Add `--video` as the second argument to record a ten-second demo with FFmpeg. The renderer and recorder use synthetic counters only. The script does not capture the desktop or install additional packages. Preview generation requires Qt's `qml` executable; video encoding also requires FFmpeg with libvpx support.

## Design and behavior

- Art is procedural and original; keep static illustration separate from lightweight motion.
- Measurements must stay honest. Unavailable data is not zero. A disappeared process is not a successfully completed job.
- No network requests, application content, credentials, or retained activity history.
- Preserve keyboard access, reduced motion, readable contrast, and compact layouts.
- Test stop/restart paths, multiple monitors, and removal whenever touching lifecycle code.
- Screenshot fixtures must use the labeled demonstration mode, never private user activity.

Contributions are licensed under the repository's MIT license.
