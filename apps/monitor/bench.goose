// Render the real process table; --window includes Retina/AppKit presentation.
import mygoose_charts from "../../extras/charts";
import monitor from ".";
import mygoose from "../..";
import mygoose_graphics from "../../extras/graphics";
import mygoose_images from "../../extras/images";
import mygoose_window from "../../extras/window";
import std;
import os;

// Real one-second collection cadence, including AppKit work between repaints.
fn steady(s: mygoose::Monitor&, c: mygoose::Context&, cache: mygoose::SceneCache&, trace: bool, settled: bool) {
    let start = mygoose::mg_clock_ns();
    let warmup: i64 = if settled { 65000000000 } else { 6000000000 };
    let duration: i64 = if settled { 30000000000 } else { 12000000000 };
    var measured: i64 = 0; var cpu: i64 = 0; var samples: i32 = 0; var sample_ms: f64 = 0.0;
    var wait_cpu: i64 = 0; var sample_cpu: i64 = 0; var build_cpu: i64 = 0; var paint_cpu: i64 = 0;
    var region_area: f64 = 0.0; var painted_area: f64 = 0.0; var region_count: i64 = 0; var sparse_frames: i32 = 0;
    var paints: i32 = 0; var builds: i32 = 0; var dirty_area: f64 = 0.0; var events: i32[16] = [0; 16];
    s.last_sample = start;
    while mygoose::mg_clock_ns() - start < warmup + duration {
        let remaining = max(1, 1000 - ((mygoose::mg_clock_ns() - s.last_sample) / 1000000) as! i32);
        var phase = if trace { mygoose::mg_cpu_ns() } else { 0 };
        let kind = mygoose::mg_wait(remaining); if kind < 0 { break; }
        if trace && measured > 0 { wait_cpu += mygoose::mg_cpu_ns() - phase; if kind < 16 { events[kind] += 1; } }
        let now = mygoose::mg_clock_ns();
        if trace { phase = mygoose::mg_cpu_ns(); }
        if now - s.last_sample >= 1000000000 {
            s.last_sample = now; mygoose::mon_sample();
            if measured > 0 { sample_ms += mygoose::mon_value(19); samples += 1; }
        }
        if trace && measured > 0 { sample_cpu += mygoose::mg_cpu_ns() - phase; }
        if trace { phase = mygoose::mg_cpu_ns(); }
        if kind == 8 { c.force = true; c.widths = [mygoose::WidthEntry {}; 512]; }
        mygoose::send(c, mygoose::Event { kind: kind, x: mygoose::mg_event_x(), y: mygoose::mg_event_y() });
        mygoose::build_frame(c, s, mygoose::mg_width(), mygoose::mg_height(), mygoose::monitor_view);
        mygoose_window::sync(s.frame, c);
        let dirty = mygoose::damage(c, cache);
        if trace && measured > 0 { build_cpu += mygoose::mg_cpu_ns() - phase; builds += 1; }
        if trace { phase = mygoose::mg_cpu_ns(); }
        if dirty { mygoose::monitor_paint(c); }
        if trace && measured > 0 {
            paint_cpu += mygoose::mg_cpu_ns() - phase;
            if dirty {
                region_count += c.regions.rects.len;
                if c.paint_regions > 1 { sparse_frames += 1; }
                for r in c.regions.rects { region_area += r.w as! f64 * r.h as! f64 / (c.width as! f64 * c.height as! f64); }
                painted_area += mygoose::paint_area(c) as! f64 / (c.width as! f64 * c.height as! f64);
                paints += 1; dirty_area += c.dirty.w as! f64 * c.dirty.h as! f64 / (c.width as! f64 * c.height as! f64); }
        }
        if measured == 0 && now - start >= warmup { measured = mygoose::mg_clock_ns(); cpu = mygoose::mg_cpu_ns(); }
    }
    let elapsed = mygoose::mg_clock_ns() - measured;
    print("steady page=", s.page, " duration_ns=", elapsed,
        " cpu_percent=", (mygoose::mg_cpu_ns() - cpu) as! f64 * 100.0 / elapsed as! f64,
        " rss_bytes=", mygoose::mg_memory_bytes(), " processes=", mygoose::mon_value(15),
        " sample_ms=", sample_ms / max(1, samples) as! f64);
    if trace { print("trace samples=", samples, " builds=", builds, " paints=", paints,
        " sample_cpu_ns=", sample_cpu, " build_cpu_ns=", build_cpu, " paint_cpu_ns=", paint_cpu, " wait_cpu_ns=", wait_cpu,
        " mean_dirty_fraction=", dirty_area / max(1, paints) as! f64,
        " mean_region_fraction=", region_area / max(1, paints) as! f64, " mean_region_count=", region_count as! f64 / max(1, paints) as! f64,
        " mean_painted_fraction=", painted_area / max(1, paints) as! f64, " sparse_frames=", sparse_frames,
        " empty_events=", events[0], " timers=", events[9], " mouse_moves=", events[1], " resize=", events[8], " frames=", events[15]); }
}
fn main() {
    let arguments = args(); var window = false; var live = false; var overview = false; var trace = false; var settled = false;
    for arg in arguments { if arg == "--window" { window = true; } if arg == "--steady" { live = true; } if arg == "--overview" { overview = true; } }
    for arg in arguments { if arg == "--trace" { trace = true; } if arg == "--settled" { settled = true; } }
    assert(!live || window); // Headless waits do not block.
    assert(mygoose::mg_open("MyGoose scroll benchmark", 1240, 820, !window));
    var s = mygoose::Monitor { page: if overview { 0 } else { 1 }, paused: true };
    if window { mygoose_window::attach(s.frame, 700.0, 480.0); }
    var c = mygoose::Context {}; c.theme = mygoose::monitor_theme();
    var cache = mygoose::SceneCache {};
    mygoose::mon_sample();
    mygoose::build_frame(c, s, mygoose::mg_width(), mygoose::mg_height(), mygoose::monitor_view);
    mygoose::mon_icons_wait();
    if live {
        if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
        steady(s, c, cache, trace, settled);
        mygoose::mon_icons_close(); mygoose::mon_close();
        if window { mygoose_window::detach(s.frame); } mygoose::mg_close(); return;
    }
    var times: i64[500] = [0; 500];
    let memory = mygoose::mg_memory_bytes();
    for frame in 560 {
        let start = mygoose::mg_clock_ns();
        mygoose::send(c, mygoose::Event { kind: 4, x: 500.0, y: 250.0, delta: -2.5, scroll_pixels: true });
        mygoose::build_frame(c, s, mygoose::mg_width(), mygoose::mg_height(), mygoose::monitor_view);
        if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
        let elapsed = mygoose::mg_clock_ns() - start;
        if frame >= 60 { times[frame - 60] = elapsed; }
    }
    var total: i64 = 0; var over60: i32 = 0; var over120: i32 = 0;
    for elapsed in times { total += elapsed; if elapsed > 16666667 { over60 += 1; } if elapsed > 8333333 { over120 += 1; } }
    // Sort outside the measured interval for percentiles.
    for i in 1..times.len {
        let value = times[i]; var j = i;
        while j > 0 && times[j - 1] > value { times[j] = times[j - 1]; j -= 1; }
        times[j] = value;
    }
    print("process-table window=", window, " rows=", s.visible, " samples=", times.len,
        " ns/frame mean=", total / times.len, " p50=", times[250], " p95=", times[475], " max=", times[499],
        " over60Hz=", over60, " over120Hz=", over120,
        " memory_delta_bytes=", mygoose::mg_memory_bytes() - memory);
    print("CPU frame cost including presentation submission; this does not measure display refresh FPS.");
    mygoose::mon_icons_close(); mygoose::mon_close();
    if window { mygoose_window::detach(s.frame); }
    mygoose::mg_close();
}
