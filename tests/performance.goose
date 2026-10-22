import .test_support;
import mygoose from "..";
import mygoose_charts from "../extras/charts";
import mygoose_performance from "../apps/performance";
import std;

fn measurements() {
    var m = mygoose_performance::Metrics {};
    mygoose_performance::reset_metrics(m, 1000000000, 2000000000);
    m.memory_mb = 42.0;
    for i in 1..17 {
        mygoose_performance::record(m, 1000000000 + i * 16666667, 2000000000 + i * 6000000,
            1000000, 2000000, 6000000, true, true, 16666667);
    }
    assert(m.origin_ns == 1000000000 && m.begin_history[0] == 1000000000 && m.end_history[0] == 1250000005);
    assert(m.count == 1 && abs(m.fps - 60.0) < 0.01);
    assert(abs(m.build_ms - 1.0) < 0.001 && abs(m.paint_ms - 2.0) < 0.001 && abs(m.cpu_ms - 6.0) < 0.001);
    assert(abs(m.cpu_percent - 36.0) < 0.01 && m.memory_history[0] == 42.0 && m.total_late == 0);
    assert(abs(m.worst_ms - 16.666667) < 0.01);
    for i in 1..131 {
        mygoose_performance::record(m, 1266666672 + i * 250000000, 2096000000 + i * 1000000,
            1000000, 0, 1000000, true, true, 16666667);
    }
    assert(m.end_history[(m.head + 119) % 120] == 1266666672 + 130 * 250000000);
    assert(m.count == 120 && m.head >= 0 && m.head < 120 && m.total_late > 100);
    mygoose_performance::reset_metrics(m, 1000000000, -1);
    mygoose_performance::record(m, 1250000000, -1, 1000, 0, -1, false, false, 16666667);
    assert(m.fps == 0.0 && m.cpu_ms == -1.0 && m.cpu_percent == -1.0 && m.total_late == 0 && m.worst_ms == -1.0);
    print("PASS: measured FPS, CPU versus wall time, memory history, late intervals, wrap/reset and unavailable counters\n");
}
fn frame(s: mygoose_performance::Performance&, c: mygoose::Context&, cache: mygoose::SceneCache&, width: f32 = 1000.0) {
    mygoose_performance::build(s,c,width,760.0);
    assert(c.count < 1024 && c.text_count < 65536);
    test_support::paint_checked(c, cache, mygoose_charts::paint);
}

fn click(s: mygoose_performance::Performance&, c: mygoose::Context&, cache: mygoose::SceneCache&, key: const u8[:]) {
    let r = mygoose::find(c, key); let x = r.x + r.w * 0.5; let y = r.y + r.h * 0.5;
    mygoose::send(c, mygoose::Event { kind: 2, x: x, y: y }); frame(s, c, cache);
    mygoose::send(c, mygoose::Event { kind: 3, x: x, y: y }); frame(s, c, cache);
}
fn has_text(c: mygoose::Context&, text: const u8[:]) -> bool {
    for i: i32 in c.count { if c.nodes[i].kind == 2 && mygoose::node_text(c,i) == text { return true; } } false
}
fn hover_cases() {
    var s = mygoose_performance::Performance { now_ns: 2000000000, hover_enabled: true };
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    mygoose_performance::reset_metrics(s.metrics,1000000000,0);
    for i in 1..4 { mygoose_performance::record(s.metrics,1000000000 + i * 266666667,i * 1000000,1000000,2000000,1000000,true,true,16666667); }
    let latest = (s.metrics.head + 119) % 120; s.metrics.fps_history[latest] = 0.0;
    frame(s,c,cache);
    let first = c.nodes[s.chart_nodes[0]].rect; let x = first.x + 12.0 + 119.5 * (first.w - 24.0) / 120.0;
    mygoose::send(c,mygoose::Event { kind: 1, x: x, y: first.y + 10.0 }); frame(s,c,cache);
    assert(s.hover_kind == 0 && s.hover_index == latest && c.parent == -1);
    assert(has_text(c,"Time +0.533–0.800 s") && has_text(c,"Window 266.7 ms · ~0.0 s ago") && has_text(c,"0.0 fps"));
    // A stationary hover must not force redraws just because wall time passed.
    frame(s,c,cache); s.now_ns += 16000000;
    mygoose_performance::build(s,c,1000.0,760.0); assert(!mygoose::damage(c,cache));
    let panel = mygoose::find(c,"hover-panel");
    assert(panel.x >= 0.0 && panel.y >= 104.0 && panel.x + panel.w <= c.width && panel.y + panel.h <= c.height);
    assert(mygoose::hit(c,panel.x + 2.0,panel.y + 2.0) == 0); // Passive overlay.
    let second = c.nodes[s.chart_nodes[1]].rect;
    mygoose::send(c,mygoose::Event { kind: 1, x: second.x + second.w - 13.0, y: second.y + 10.0 }); frame(s,c,cache);
    assert(s.hover_kind == 1 && has_text(c,"Layout 1.0 ms · Paint 2.0 ms") && has_text(c,"Total 3.0 ms"));
    // Unavailable readings retain their time range instead of becoming zero.
    let third = c.nodes[s.chart_nodes[2]].rect; s.page.offset += third.y - 250.0; frame(s,c,cache);
    let cpu = c.nodes[s.chart_nodes[2]].rect; s.metrics.frame_cpu_history[latest] = -1.0;
    mygoose::send(c,mygoose::Event { kind: 1, x: cpu.x + cpu.w - 13.0, y: cpu.y + 10.0 }); frame(s,c,cache);
    assert(s.hover_kind == 2 && has_text(c,"Unavailable"));
    s.page.offset = 0.0; frame(s,c,cache);
    mygoose::send(c,mygoose::Event { kind: 1, x: second.x + second.w - 13.0, y: second.y + 10.0 }); frame(s,c,cache);
    // An actual 400 ms bucket must not be described as a nominal 250 ms slot.
    mygoose_performance::record(s.metrics,2200000000,4000000,0,0,0,true,true,16666667); s.now_ns = 2300000000; frame(s,c,cache);
    assert(has_text(c,"Time +0.800–1.200 s") && has_text(c,"Window 400.0 ms · ~0.0 s ago"));
    // Empty padding, leaving the chart and reset remove both tooltip and guide.
    mygoose::send(c,mygoose::Event { kind: 1, x: first.x + 13.0, y: first.y + 10.0 }); frame(s,c,cache); assert(s.hover_kind == -1);
    mygoose::send(c,mygoose::Event { kind: 1, x: x, y: first.y + 10.0 }); frame(s,c,cache); assert(s.hover_kind == 0);
    mygoose::send(c,mygoose::Event { kind: 1, x: 1.0, y: 1.0 }); frame(s,c,cache); assert(s.hover_kind == -1);
    mygoose::send(c,mygoose::Event { kind: 1, x: x, y: first.y + 10.0 }); frame(s,c,cache);
    s.light = true; frame(s,c,cache,480.0);
    let narrow = c.nodes[s.chart_nodes[0]].rect;
    mygoose::send(c,mygoose::Event { kind: 1, x: narrow.x + narrow.w - 13.0, y: narrow.y + 10.0 }); frame(s,c,cache,480.0);
    assert(s.hover_kind == 0); let small_panel = mygoose::find(c,"hover-panel"); assert(small_panel.x + small_panel.w <= 480.0);
    mygoose::send(c,mygoose::Event { kind: 7 }); frame(s,c,cache,480.0); assert(s.hover_kind == -1 && !s.hover_enabled);
    s.light = false; frame(s,c,cache);
    mygoose_performance::reset_metrics(s.metrics,2400000000,4000000); frame(s,c,cache); assert(s.hover_kind == -1);
    // Clipping excludes a chart hidden under the fixed header, even if the
    // pointer lies inside its un-clipped plot rectangle.
    mygoose_performance::record(s.metrics,2800000000,5000000,0,0,0,true,true,16666667); s.now_ns = 2900000000;
    s.page.offset = first.y - 50.0; frame(s,c,cache);
    let hidden = c.nodes[s.chart_nodes[0]].rect;
    mygoose::send(c,mygoose::Event { kind: 1, x: hidden.x + hidden.w - 13.0, y: hidden.y + 10.0 }); frame(s,c,cache);
    assert(s.hover_kind == -1);
    print("PASS: exact hover timestamps/duration, zero/stacked values, history advance, empty/reset/exit, passive overlays and partial/full pixels\n");
}
fn paused_interaction() {
    var s = mygoose_performance::Performance { paused: true, spike: true };
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    assert(mygoose_performance::render(s,c,cache,true,0).painted);
    let phase = s.phase; let checksum = s.checksum;
    mygoose_performance::work(s);
    assert(s.phase == phase && s.checksum == checksum && s.spike);
    var pixels = mygoose::mg_pixel_hash();
    // No workload/chart deadline is due during these closely spaced events.
    // Every wheel event must reach the framebuffer, including fractional input.
    for i in 12 {
        mygoose::send(c,mygoose::Event { kind: 4, x: 500.0, y: 650.0, delta: -2.5, scroll_pixels: true });
        assert(mygoose_performance::render(s,c,cache,false,4).painted);
        let next = mygoose::mg_pixel_hash(); assert(next != pixels); pixels = next;
    }
    assert(s.page.offset == 30.0 && s.phase == phase && s.metrics.count == 0);
    // Paused idle waits remain idle. Active input still obeys frame pacing.
    mygoose::send(c,mygoose::Event { kind: 9 });
    assert(!mygoose_performance::render(s,c,cache,false,9).painted);
    s.paused = false;
    mygoose::send(c,mygoose::Event { kind: 4, x: 500.0, y: 650.0, delta: -2.5, scroll_pixels: true });
    assert(!mygoose_performance::render(s,c,cache,false,4).painted && s.page.offset == 32.5);
    mygoose::send(c,mygoose::Event {});
    assert(mygoose_performance::render(s,c,cache,true,0).painted);
    // Pause and resume transitions are visible before the next paced frame.
    for transition in 2 {
        let r = mygoose::find(c,"pause"); let x = r.x + r.w * 0.5; let y = r.y + r.h * 0.5;
        mygoose::send(c,mygoose::Event { kind: 2, x: x, y: y });
        mygoose_performance::render(s,c,cache,false,2);
        mygoose::send(c,mygoose::Event { kind: 3, x: x, y: y });
        assert(mygoose_performance::render(s,c,cache,false,3).painted);
        assert(s.paused == (transition == 0));
    }
    var m = mygoose_performance::Metrics {};
    mygoose_performance::reset_metrics(m,1000000000,0);
    for i in 1..16 { mygoose_performance::record(m,1000000000 + i * 16666667,i * 1000000,1000,2000,1000000,true,false,16666667); }
    assert(abs(m.fps - 60.0) < 0.01 && m.total_late == 0 && m.worst_ms == -1.0);
    print("PASS: paused input paints immediately, workload stays stopped, idle stays idle, transitions repaint and active input remains paced\n");
}
fn dirty_area_cases() {
    var s = mygoose_performance::Performance { metrics: mygoose_performance::Metrics { count: 1 }, paused: true };
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    assert(mygoose_performance::render(s,c,cache,true,0).painted);
    assert(mygoose::paint_area(c) == c.width * c.height && c.paint_regions == 1);
    assert(s.dirty_percent == 0.0); // Off-screen footer does no diagnostic work.
    // The view applies its theme after begin; settle the initial root stamp.
    mygoose_performance::render(s,c,cache,true,0);
    s.phase = 0.5; s.metrics.fps = 75.0;
    assert(mygoose_performance::render(s,c,cache,true,0).painted);
    assert(s.dirty_percent == 0.0);
    // Reveal the footer, then change separate counters in its two rows.
    s.page.offset = c.nodes[s.dirty_node].rect.y - 600.0;
    assert(mygoose_performance::render(s,c,cache,true,0).painted);
    assert(s.dirty_percent > 0.0);
    s.clicks += 1; s.checksum += 1;
    assert(mygoose_performance::render(s,c,cache,true,0).painted);
    let bounding_percent = mygoose::rect_area(c.dirty) * 100.0 / (c.width * c.height);
    assert(s.dirty_percent > 0.0);
    if c.paint_regions > 1 {
        assert(s.dirty_percent < bounding_percent);
    } else { assert(abs(s.dirty_percent - bounding_percent) < 0.01); }
    // An explicit full dirty override reports full coverage on every backend.
    c.dirty = mygoose::Rect { w: c.width, h: c.height }; mygoose_charts::paint(c);
    assert(c.paint_regions == 1 && mygoose::paint_area(c) == c.width * c.height);
    assert(!mygoose::damage(c,cache) && mygoose::paint_area(c) == 0.0);
    print("PASS: Performance reports visible sparse paint area, skips hidden diagnostics, handles fallback and overrides\n");
}
fn main() {
    measurements();
    var capped = mygoose_performance::Performance { rate: 2, synced: true, display_hz: 60 };
    assert(mygoose_performance::target(capped)==120 && mygoose_performance::effective_target(capped)==60);
    assert(mygoose_performance::period_ns(capped)==1000000000/60);
    capped.display_hz = 120; assert(mygoose_performance::effective_target(capped)==120);
    capped.synced = false; capped.display_hz = 60; assert(mygoose_performance::effective_target(capped)==120);
    mygoose::headless_open(1000,760); dirty_area_cases(); hover_cases(); paused_interaction(); var s = mygoose_performance::Performance {};
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    frame(s,c,cache);
    s.metrics.fps_history[0] = 600.0; frame(s,c,cache);
    let expanded = s.chart_scales[0]; assert(expanded >= 600.0);
    s.metrics.fps_history[0] = 0.0; frame(s,c,cache);
    assert(s.chart_scales[0] == expanded); // Old bars must not breathe as peaks leave the window.
    click(s,c,cache,"pause"); assert(s.paused);
    click(s,c,cache,"reset"); assert(s.reset);
    s.tiles = 96.0; s.phase = 0.37; frame(s,c,cache);
    // Reveal the controls and check that the spike button queues real work.
    s.page.offset = mygoose::find(c,"spike").y - 250.0; frame(s,c,cache);
    click(s,c,cache,"spike"); assert(s.spike);
    click(s,c,cache,"light"); assert(s.light);
    // Reveal the first workload tile and select it.
    let tile = mygoose::find(c,"tile"); s.page.offset += tile.y - 220.0; frame(s,c,cache);
    click(s,c,cache,"tile"); assert(s.selected == 0 && s.clicks == 1);
    // Scroll the nested list without moving its containing page; at the
    // boundary, wheel input returns to the outer page.
    s.page.offset = s.page.content; frame(s,c,cache); frame(s,c,cache);
    assert(s.list_bounds.h > 0.0);
    let before = s.page.offset; let x = s.list_bounds.x + 50.0; let y = s.list_bounds.y + 20.0;
    mygoose::send(c, mygoose::Event { kind: 4, x: x, y: y, delta: -12.5, scroll_pixels: true }); frame(s,c,cache);
    assert(s.list.offset == 12.5 && s.page.offset == before);
    s.list.offset = 0.0;
    mygoose::send(c, mygoose::Event { kind: 4, x: x, y: y, delta: 12.5, scroll_pixels: true }); frame(s,c,cache);
    assert(s.page.offset < before && s.list.offset == 0.0);
    s.page.offset = 0.0; mygoose::send(c, mygoose::Event {}); frame(s,c,cache,480.0);
    mygoose::mg_close();
    print("PASS: performance dashboard, max workload, pause/reset/spike/theme/selection, nested scrolling, narrow reflow and partial/full pixels\n");
}
