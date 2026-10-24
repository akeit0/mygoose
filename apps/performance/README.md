# Performance lab

A native, scrollable sample app for exploring rendering performance while
interacting with a live UI. It uses the core controls and optional chart package;
there is no monitor sampler, webview, vector dependency or external service.

```sh
python3 tools/build.py performance --mode small --run
python3 tools/macos.py performance --install
python3 tools/build.py performance-test --mode debug
```

The six charts show painted frames/second, layout + paint/submission wall time,
process CPU time per update, process CPU utilization, worst interval between
paint submissions, and resident memory. Histories hold 120 measured 250 ms
buckets (about 30 seconds). Each vertical bar represents one bucket. New bars
arrive on the right, shifting old bars left by exactly one slot every sampling
tick; there is no movement/interpolation between ticks or width-based resampling.
Hover a recorded bar to inspect its exact time range since Reset, actual bucket
width, approximate age and measured values. Layout/paint bars show both channels and their
total. A vertical guide identifies the selected slot; unavailable counters stay
explicitly unavailable. Leading empty slots have no tooltip. The tooltip follows
current layout/clipping and stays inside the visible page without taking focus
or mouse capture. Age is measured at the latest completed sampling edge, so a
stationary tooltip does not trigger extra redraws between sampling ticks. Mouse
movement uses the selected frame cadence while the workload is running.

Vertical scales hold steady, expand in steps only when needed and reset with
the history. The chart footer shows the top of the scale. Empty/unavailable
measurements stay blank. CPU time
comes from `CLOCK_PROCESS_CPUTIME_ID` on macOS/Linux and `GetProcessTimes` on
Windows, excluding idle waits; CPU utilization uses 100% for one core.
The update CPU timer covers work/layout/paint calls. Whole-process utilization
also includes AppKit event dispatch and asynchronous presentation work that runs
between those calls; it can therefore exceed update time × frame rate.
The memory chart reports RSS. macOS physical footprint also accounts for graphics
allocations, so reductions in window backing storage may show much more clearly
in physical footprint than in this chart. The Mac renderer presents in sRGB/SDR
at the display's full backing resolution.

FPS counts actual calls that paint/submit a frame. It does not measure display
refresh, compositor presentation, GPU completion or input latency. Layout and
paint charts use wall-clock durations; CPU time also includes the optional busy
work. The worst interval is the largest active-workload interval in each bucket.
A late frame exceeds 1.5 times the selected target interval. Targets request 30/60/120 frames per second. On macOS 14+, the window's
`CADisplayLink` supplies synchronized frame events on the main thread. Animation
samples use predicted presentation timestamps, while all timing metrics continue
to measure actual work and paint submissions. The UI reports display sync, the
display's maximum Hz and a limit message when the target exceeds it. A 60 Hz
display caps a 120 FPS request at 60; 120 distinct frames require a 120 Hz display.
The frame budget and late-frame threshold use this effective target.

While running, mouse, keyboard and IME events are consumed immediately and painted
on the next frame; they cannot bypass the cap. Unsupported backends and paused sampling use
the core `FramePacer` with absolute monotonic deadlines, skipping missed slots
instead of running a catch-up burst. Display callbacks stop for off-screen
windows. Pausing disables display sync and samples charts at roughly 4 Hz.
Paused scrolling, hovering, controls, typing and resizing repaint immediately on
input, independently of that sampling clock. These interaction paints count in
the measured FPS, without restarting the workload or postponing sampling.

Change CPU work (0–12 ms/frame), select 8–96 animated tiles, or inject a single
24 ms CPU-work spike. Click tiles, type Unicode text, switch theme, and scroll
10,000 virtual rows. The page and list scroll independently, with wheel input
returning to the page at list boundaries. Resizing reflows cards and tiles.
Windows mouse-wheel notches update a destination sampled on every frame and
preserve velocity through continuous input. Moving the pointer does not
interrupt the page or list's motion. Paused scrolling also animates; fractional
wheel input and macOS native scrolling remain direct.
Pause stops the continuous workload while charts sample at roughly 4 Hz; Reset
clears timing/history counters. A small header animation remains visible while
running so FPS can be measured even with the tile grid below the viewport.

The footer's Dirty area is the logical bitmap area repainted on the last
submission, divided by the window area. It uses the core `paint_area` diagnostic:
separate regions leave gaps out, and overlapping regions count only once.
Fallback backends report their enclosing rectangle because they repaint its
gaps too. It does not measure compositor coverage or snapshot/upload size.
The footer refreshes this diagnostic only while it is inside the scroll
viewport. The union calculation uses bounded scratch arrays and runs only when
this metric is requested; ordinary library windows do not pay for it.

The test target checks timing math with known intervals, history wrap/reset,
unavailable CPU counters, workload limits, interaction, nested scrolling,
responsive layout and partial/full repaint equality. `all` builds the app and
runs its tests. The native package-build route also works:

```sh
goose build --cc clang -o build/performance examples/performance.goose
```

For a bounded native timing check, build `python3 tools/build.py performance-bench`
and run `build/macos-small/performance-bench --bench-60`
(or `--bench-30` / `--bench-120`). It warms up for one second, measures four
seconds of actual paint submissions, reports build/paint/wait time, process CPU
utilization, ending and sampled peak resident memory, average
absolute interval jitter and the worst paint interval, then exits. Add `--timer` after the rate flag to compare the
absolute timer mode against display sync. These are submission measurements,
not compositor/scanout measurements. On a 60 Hz Mac the synchronized 120 target
is expected to report about 60 FPS. The display link follows the window's screen
([Apple's window display link](https://developer.apple.com/documentation/appkit/nswindow/displaylink(target:selector:))).

Add `--steady` to warm up for 32 seconds and measure eight seconds with a full
history. Use this to distinguish steady rendering cost from startup and short
histories; each run exits after about 40 seconds.
