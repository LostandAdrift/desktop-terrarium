# Desktop Terrarium telemetry

Read-only Linux collector. It prints one JSON object per line (NDJSON) from aggregate kernel counters and same-user process names. It does not persist state, open network sockets, spawn subprocesses, or change the machine.

## Command

```
python3 -u scripts/collect.py --interval 2
python3 -u scripts/collect.py --once
python3 -u scripts/collect.py --once --proc-root /path/to/fake/proc
```

- `--interval` is the target sleep between stream samples. Allowed range is `[1, 60]` seconds. Values outside that range are an argparse error, not a silent clamp. Default is `2`.
- `--once` emits a single sample immediately and exits. There is no delay. Rate fields that need two observations are `null`.
- `--proc-root` defaults to `/proc`. Tests pass a synthetic tree. The live collector must not be pointed at arbitrary filesystem paths that are not procfs-shaped.
- Stream mode continues until stdin EOF on a TTY/pipe/socket, `SIGINT`, `SIGTERM`, `SIGHUP`, or a broken stdout pipe. `/dev/null` stdin is not treated as EOF. Each line is flushed. Failures still wait out the interval so the process cannot busy-loop.
- The module is importable: `Collector`, `collect_once`, parsers, and `main(argv)`.

No files are written. Previous counters live only in process memory for delta math.

## JSON contract

Every line is a single object with these fields, spelled exactly:

| Field | Meaning |
| --- | --- |
| `version` | Always integer `1`. |
| `timestamp` | Unix epoch seconds (`time.time`, truncated to int). |
| `interval` | Actual `time.monotonic` delta since the previous sample from this process, or `0` on the first/`--once` sample. This is measured elapsed time, not the configured `--interval`. |
| `cpu` | Busy share of **all CPUs together**, `0`–`100`. `null` on the first sample, when `/proc/stat` is unreadable, or when the aggregate counters reset. Never fabricated as `0` on those error paths. |
| `memory.usedBytes` | Estimated in-use anonymous/file-backed RAM, bytes. |
| `memory.totalBytes` | `MemTotal`, bytes. |
| `memory.percent` | `usedBytes / totalBytes * 100`, clamped to `0`–`100`, or `null` if total is unknown. |
| `network.rxBytesPerSec` | Sum of receive byte rates on counted interfaces. `null` until a comparable prior sample exists. Non-negative. |
| `network.txBytesPerSec` | Same for transmit. |
| `network.interfaces` | Sorted kernel names of counted interfaces in this sample. |
| `processes` | At most seven groups. See below. |
| `processCount` | Count of every accessible same-user, non-zombie process, including groups that did not rank into `processes`. |
| `uptimeSeconds` | First field of `/proc/uptime` (seconds). `0` if unreadable, with an error. |
| `errors` | Short, non-sensitive English notes. Never paths, never PIDs, never command lines. |

A process group object:

| Field | Meaning |
| --- | --- |
| `key` | Stable identity: sanitized comm, lowercased, max 64 characters. Not a PID. |
| `name` | Sanitized comm as displayed (controls stripped, max 64 characters). |
| `count` | Number of live processes in the group. No PID array is emitted. |
| `cpu` | Sum of members' CPU, same units as top-level `cpu` (percent of whole-machine capacity). `null` when no member has a valid delta. |
| `memoryBytes` | Sum of resident set size (RSS) in bytes. |
| `category` | One of `browser`, `editor`, `terminal`, `agent`, `media`, `system`, `other`. |

## Counters

### CPU (`/proc/stat`)

The aggregate `cpu ` line (not `cpu0`) is used. `guest` and `guest_nice` are ignored because Linux already folds them into `user` and `nice`.

```
idle_ticks  = idle + iowait
total_ticks = idle_ticks + user + nice + system + irq + softirq + steal
cpu%        = 100 * (Δtotal - Δidle) / Δtotal
```

If `total` moves backwards, the window is a counter reset: `cpu` is `null` and the new counts become the baseline. A zero `Δtotal` is also `null`. Idle deltas are clamped into `[0, Δtotal]` so a glitch cannot produce values outside `0`–`100`.

Process CPU uses the same tick domain. For each `(pid, starttime)` pair:

```
proc% = 100 * Δ(utime + stime) / Δmachine_total
```

That is a share of **entire machine capacity**, not of a single core. `100` would mean the group consumed every CPU. A new process, a PID reused with a different `starttime`, a tick decrease, or a missing machine delta yields `null` for that member rather than a spike.

### Memory (`/proc/meminfo`)

Values are converted from kB (KiB) to bytes.

Preferred:

```
usedBytes = MemTotal - MemAvailable
```

If `MemAvailable` is absent (older kernels / incomplete fixtures):

```
usedBytes = MemTotal - MemFree - Buffers - Cached - SReclaimable + Shmem
```

`usedBytes` is clamped to `[0, totalBytes]`. Missing `MemTotal` leaves `usedBytes=0`, `totalBytes=0`, `percent=null`.

RSS for a process is `VmRSS` from `/proc/<pid>/status` (kB → bytes). If that line is missing, `stat` field 24 (`rss`, pages) × page size is used.

### Network (`/proc/net/dev`)

Receive bytes are field 1 after the colon; transmit bytes are field 9. Interfaces named `lo` / `lo:*`, or prefixed `veth`, `docker`, or `br-`, are ignored.

Rates are per-interface, then summed:

- First sample, or no successful prior read: both rates `null`.
- Interface present now but not in the prior map: no contribution (arrival must not look like a burst from zero).
- Interface gone: dropped from the list; it does not contribute.
- Byte counter lower than last time on that direction: that direction is skipped (reset), independently of the other direction.

If the file cannot be read, rates are `null` and the prior map is discarded so the next successful read cannot combine a two-interval byte delta with a one-interval clock delta.

### Uptime (`/proc/uptime`)

First whitespace-separated field, seconds, as a finite non-negative number.

### Processes (`/proc/<pid>/`)

Only numeric directory names are considered. For each candidate the collector may read `stat`, `status`, and `comm`. It never opens `cmdline`, `environ`, `cwd`, `exe`, `fd/`, `maps`, or `smaps`.

Included when all of the following hold:

- The PID is not the collector itself.
- `stat` parses (comm may contain spaces and `)`; the kernel delimiter is the **last** `)`).
- State is not zombie/dead (`Z` or `X`).
- Real UID from `status` (`Uid:` first number) equals the collector UID. If `status` has no UID, directory owner is used. This gate is independently testable with `--proc-root` plus `Collector(uid=...)`.
- Transient `OSError` / permission / vanish: skip that PID, keep going.

`processCount` is that filtered population, bounded by a scan cap (4096). Groups share a `key`. Ranking takes the top 7 by `2 * cpu + memoryPercent` (null CPU counts as 0), then `key` for ties. CPU is weighted more than memory so a busy small process outranks a large idle one, but a large idle process can still surface when CPU is quiet.

## Privacy boundary

Collected:

- Aggregate CPU, memory, uptime.
- Aggregate byte rates and kernel interface names, excluding loopback and common container bridges. Other virtual interfaces can be included, so VPN/tunnel traffic may be counted at multiple layers.
- Executable comm (kernel thread name, truncated by the kernel, then sanitized).
- Per-group counts, RSS sums, and inferred category from that name.
- Numeric UID, used only as an include/exclude gate, never emitted.

Never collected:

- Command lines, environment, credentials, tokens.
- Window titles, browser URLs, file contents, cwd, open fds, maps.
- User names, home paths, hostnames, IP addresses, socket tables.
- PID lists.
- Anything off-box. There is no HTTP client and no cloud endpoint.

Names and error strings are stripped of control characters and truncated. Error text is a fixed short phrase such as `cpu counters unreadable`. The proc root path is never interpolated into output.

Treat process disappearance as disappearance. The collector does not decide that a job “completed successfully.”

## Resource bounds

- At most 7 process groups, 64 interface names, 8 error strings, 64 characters per emitted name.
- At most 4096 `/proc` PID directories visited per sample.
- Individual proc files are read with a 64 KiB cap.
- Stream wait uses `select`/`sleep` in ≤0.5 s slices. It does not spin.
- The plugin stops its collector when closed or switched into demonstration mode. Quickshell owns the child process lifecycle. Closing a stdout pipe or receiving SIGTERM also stops the collector; simply ceasing to read stdout is not sufficient.
