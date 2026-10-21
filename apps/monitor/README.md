# MyGoose Activity Monitor

MyGoose Activity Monitor's visual design closely follows
[Pulse](https://pulse.egoist.dev/) by EGOIST. It is implemented with Goose,
[MyGoose](../../README.md) and native C, without using Pulse's source code.
This is an unofficial project, unaffiliated with Pulse.

The UI is Goose; application-specific C reads operating system counters. It
uses no helper service, webview, bundled fonts or application telemetry.

```sh
python3 tools/build.py monitor --run
python3 tools/build.py monitor-test --mode small
```

Outputs are `build/macos-small/monitor`, `build/linux-small/monitor`, and
`build/small/monitor.exe` on Windows. Use `python` on Windows; `--console`
enables diagnostic output. On macOS, `python3 tools/macos.py monitor --install`
creates `~/Applications/MyGoose/MyGoose Activity Monitor.app`. Goose package
builds also work: `goose build --cc clang apps/monitor/main.goose`.

## Views and interaction

- Overview shows CPU, memory, GPU, disk, network and process cards, plus ranked
  processes. Its cards reflow and scroll at smaller window sizes.
- Processes provides name/PID search, sorting, resizable/reorderable columns,
  row selection, keyboard navigation and a virtualized table. Less important
  columns hide at narrow widths; the inspector replaces the table when needed.
- CPU shows total/user/system/idle usage, a responsive logical-processor grid
  and top processes. Only visible grid rows plus overscan are built.
- Memory shows used/available memory, utilization rings, cache and process
  tiles. Click a tile/ranked process to inspect it; Show All opens the sorted
  process table. Summary cards stack at narrow widths.
- GPU shows Windows engine usage and dedicated/shared memory. Disk and Network
  show stacked read/write or download/upload histories. Unsupported readings
  remain unavailable rather than becoming zero.
- The process inspector shows CPU/memory history, threads, CPU time, I/O,
  state and executable path. Its content scrolls independently. Selection uses
  PID and creation time, so PID reuse does not transfer it to another process.
- About shows host, processor, memory, uptime and sample time.

The search field moves between the caption and a separate row as space allows.
Its icon and unused interior focus the input; Clear empties it and returns
focus. Ctrl+F opens Processes and selects the query. Escape first belongs to
an active IME; otherwise it clears a query, then removes search focus. Search
focus, selection and composition survive reflow. Row arrows, Home/End and
Page Up/Down reveal the selected process; Ctrl+I opens its inspector. The row
context menu supports Details, path copying and available process actions.

The caption uses an icon-only pause/resume control with an 18-point right
inset and 1m/5m/15m/1h history choices. Windows uses custom window controls;
macOS retains native traffic lights in an integrated title bar. Use
`--window-style standard` when packaging on macOS for a separate system title
bar. Linux retains native decorations. The shared
[window package](../../extras/window/README.md) supplies caption behavior.

## Sampling and platform support

One sample is collected per second. Input rebuilds the UI without taking extra
samples. Pause stops collection and waits for input; pending icon jobs can wake
the UI briefly. Resume computes rates over the full elapsed interval. History
holds 3,600 collected samples; paused time is not inserted. Range labels assume
the normal one-second cadence. The first snapshot establishes rate baselines.

| Capability | Windows | Linux | macOS |
| --- | --- | --- | --- |
| CPU, per-core, memory, processes, disk, network | Supported | Supported | Supported |
| Process icons | Executable icons | Generic fallback | Application/helper icons |
| GPU and per-process GPU | WDDM/PDH counters | Unavailable | Unavailable |
| Graceful close | Window close request | SIGTERM through pidfd | Unavailable |
| Force Quit | Process termination | SIGKILL through pidfd | Unavailable |
| Show executable location | File Explorer | File manager | Finder |

Linux process actions require `pidfd_open` support (kernel 5.3+); Windows actions
require `IsProcessCritical` (Windows 8.1+). Both verify creation time before
termination and refuse protected targets. Exited/unverified selections disable
termination. Force Quit does not close children. Folder opening can use a cached
path after exit. macOS termination is unavailable because this implementation
cannot atomically signal a verified process identity. Action failures appear in
the inspector.

Per-core sampling starts on the first CPU-page visit. Stable OS IDs survive
hotplug; missing readings remain unknown. Current values are bounded to 128
processor IDs, with an omitted-provider warning. The Windows total CPU reading
covers the calling processor group; the per-core grid uses provider instances.
Linux under WSL measures the Linux VM's activity, not Windows processes.

Windows GPU queries run only while Overview, Processes or GPU is visible.
Missing providers retry after 30 seconds while active. Storage is bounded to
128 engines and a 2 MiB counter array; exceeding a bound reports unavailable.
Adapter capacity/names, GPU temperature, Linux/macOS GPU sampling, Linux process
icons, app grouping, per-process users and machine cleanup are not implemented.

## Reading the metrics

System CPU uses 100% for total capacity. Process CPU uses **100% for one logical
processor**, so a process can exceed 100%. Ranked bars expand to the busiest
process. CPU deltas use PID plus creation time; counter resets clamp to zero.
Unavailable/inaccessible values display `—` without requesting elevation.

Memory values use binary units. Windows process memory is private working set;
Linux/macOS use resident memory. Inspector secondary memory is private commit
on Windows and virtual size on Linux/macOS. Windows private-working-set queries
require the extended process memory counters available in updated Windows
10/11 22H2; older systems retain other supported readings and show unavailable
working set. See Microsoft's
[extended counter definition](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex2).

System used memory is not the sum of process memory: sharing, caches and kernel
allocations differ. The physical-memory ring partitions used/available memory;
cache overlaps other categories. Windows/Linux commit utilization is committed
bytes divided by the commit limit, not memory pressure. Linux overcommit can
exceed 100%; the ring saturates while the percentage remains visible. macOS
uses swap readings in place of commit. Process tiles describe their displayed
top processes, not all physical memory.

Windows GPU usage is the busiest physical engine across adapters. Per-process
GPU is that process's busiest engine; values across engines must not be added.
Dedicated/shared memory readings are memory in use, not capacity or sums of
per-process allocation. New/reused identities and missing samples remain
unknown; a verified process without a GPU context shows zero once the provider
is valid. See Microsoft's
[GPU counter explanation](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/).

The inspector retains up to 60 samples since selection, combined by maximum
into up to 30 chart buckets. CPU scales to at least 100% and memory to the
observed peak. Disk and network series share their chart scale. I/O details are
queried on demand once per snapshot, including failure results; timed rates
require two successful reads for the same process identity.

## Storage and validation

The sampler owns fixed storage for 4,096 processes, previous rates and eight
3,600-sample histories. A warning reports process-capacity overflow. Windows
and macOS icons use bounded caches; unavailable images retain a vector fallback.
The sampler and icon providers belong to this app, not the UI library.

The reusable [chart package](../../extras/charts/README.md) uses one scene leaf
per chart and at most 1,480 inline bytes, with no per-dot nodes or persistent
chart textures. The core supplies scroll areas, table columns and stable list
selection. Static graphics no longer depend on motion packages, so Monitor
needs neither their root declarations nor an animation runner.

`monitor-test` covers filtering/sorting, PID reuse, missing counters, history,
CPU grids, responsive captions, column interaction, selection, inspector actions,
clipboard behavior, native controls/icons and partial/full repaint equality.
The sampler tests exercise provider failures and process identity independently
of the UI. Native chart validation is owned by `charts-test`; `all` runs both.
See [platform details](../../docs/platforms.md),
[test targets](../../CONTRIBUTING.md) and the
[benchmark guide](../../bench/README.md) for reproduction commands.
