# Benchmarks

Build first, then measure without concurrent builds or profilers. Record the
commit, Goose/native compiler versions, build mode, OS, window size, backing
scale, display rate and workload. Use the same settings for before/after runs,
warm each process and repeat trials. Keep generated reports under `build/`.

## Shared core

```sh
python3 tools/build.py bench --mode small --run
```

The benchmark measures unchanged controls, changing labels and a scrolling
10,000-row virtual list. Each workload runs build/layout/damage detection alone
and with CPU raster painting, after 20 warmup frames. Results include
nanoseconds/frame, paints, built nodes, text bytes and process memory. An
unchanged view should need no further paints. System libraries and fonts are
not included in executable size.

Mode 3 updates two labels separated by unchanged content. Its two raster runs
compare `bounds_only=true` (the bounding-rectangle fallback) with normal backend
region selection in the same executable. This isolates sparse-update cost
without changing the scene or compiler flags; dense-label and scroll modes
remain useful regression comparisons. Run several fresh processes and compare
medians rather than interpreting one short timing as a stable CPU percentage.
The timing includes rebuilding, damage calculation and painting. It measures
skipping unchanged content; live Monitor CPU also includes its OS samplers.
Keep local measurements and experimental probes under ignored `build/`.

## Monitor

```sh
python3 tools/build.py monitor-bench --mode small --run
./build/macos-small/monitor-bench --window
./build/macos-small/monitor-bench --window --steady --overview --trace
```

Replace the executable path with `build/linux-small/monitor-bench` on Linux or
`build/small/monitor-bench.exe` on Windows. The default workload renders the
process table with fractional scrolling: 60 warmup frames and 500 measured
frames, reporting mean/p50/p95/max cost and counts over 60/120 Hz frame budgets.
`--window` includes native backing scale and presentation submission.

`--steady` samples a real window at one-second intervals, warming up for six
seconds and measuring twelve. `--overview` selects Overview instead of
Processes; `--trace` separates sampler/build/paint/event-pump CPU cost.
`--settled` extends warmup to 65 seconds and measurement to 30 seconds so the
one-minute chart history is full. These runs measure the entire process,
including work performed by the OS adapter between paints.

On macOS, collect repeated trials with RSS and physical footprint:

```sh
python3 bench/measure_monitor_macos.py --app build/macos-small/monitor-bench --workloads overview processes scroll --output build/monitor-results.json
```

The probe accepts `--runs`, `--trace` and `--settled`. Close other sample apps
and keep display visibility/power conditions consistent for window comparisons.
RSS and physical footprint account for memory differently; chart backing can
be more visible in footprint than RSS.

## Performance lab

```sh
python3 tools/build.py performance-bench --mode small
./build/macos-small/performance-bench --bench-60
```

Use `--bench-30` or `--bench-120` for other targets, `--timer` to compare timed
pacing with display sync, and `--steady` for a full history. Output includes
paint submissions, FPS, layout/paint/wait durations, process CPU, resident
memory and frame-interval jitter. See the [app guide](../apps/performance/README.md)
for the chart and timing definitions.

Paint/submission FPS does not measure compositor presentation or scanout.
A 60 Hz display cannot show 120 distinct frames per second. CPU utilization
uses 100% for one core; update CPU time excludes work done between updates.
Scroll benchmarks run without refresh pacing and report cost, not display FPS.

## Native probes

The macOS rendering probe isolates dynamic text measurement and rectangle
fills; the Monitor probe isolates chart drawing, sampling and query sorting:

```sh
clang -Os -flto bench/macos.m -o build/macos-render-bench -framework Cocoa -framework CoreText -framework CoreGraphics -framework QuartzCore
clang -Os -flto bench/monitor_macos.m extras/charts/native/macos.c -o build/monitor-native-bench -framework Cocoa -framework CoreText -framework CoreGraphics -framework QuartzCore -framework IOKit
```

Both run headless. To include the Monitor native probe in repeated captures,
pass `--native build/monitor-native-bench --workloads native overview processes scroll`
to `bench/measure_monitor_macos.py`.

On Windows, `python tools/measure.py --mode small` collects executable sizes,
hidden-window working set/private bytes, an idle CPU sample and headless frame
timings into `build/small/measurements-d2d.json`. The tool requires Windows;
use the native benchmarks on other systems. Short idle samples are not peak
memory measurements, and zero sampled CPU time does not establish zero CPU use.
