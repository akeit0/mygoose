namespace mygoose_performance;
import mygoose from "../..";
import mygoose_charts from "../../extras/charts";
import std;

let blue: u32 = 0x63a4ff;
let green: u32 = 0x45d9ac;
let amber: u32 = 0xffc46b;
let purple: u32 = 0xb39aff;
let rates: const u8[:][3] = ["30 fps target", "60 fps target", "120 fps target"];
let chart_names: const u8[:][6] = ["Frame rate", "Layout + paint time", "CPU time / update", "Process CPU", "Worst frame interval", "Resident memory"];
let chart_colors: u32[6] = [blue, green, green, amber, amber, purple];
let chart_units: const u8[:][6] = [" fps", " ms", " ms", "%", " ms", " MiB"];
let history_count: i32 = 120; // 250 ms buckets, 30 seconds.
struct Metrics {
    origin_ns: i64 = 0, start_ns: i64 = 0, cpu_start_ns: i64 = -1, last_present_ns: i64 = 0,
    frames: i64 = 0, builds: i64 = 0, build_ns: i64 = 0, paint_ns: i64 = 0, frame_cpu_ns: i64 = 0,
    worst_ns: i64 = 0, late: i64 = 0, total_late: i64 = 0,
    fps: f32 = 0.0, cpu_ms: f32 = -1.0, build_ms: f32 = 0.0, paint_ms: f32 = 0.0,
    cpu_percent: f32 = -1.0, worst_ms: f32 = -1.0, memory_mb: f32 = -1.0,
    fps_history: f32[120] = [-1.0; 120], cpu_history: f32[120] = [-1.0; 120],
    build_history: f32[120] = [-1.0; 120], paint_history: f32[120] = [-1.0; 120],
    memory_history: f32[120] = [-1.0; 120], interval_history: f32[120] = [-1.0; 120],
    frame_cpu_history: f32[120] = [-1.0; 120],
    begin_history: i64[120] = [0; 120], end_history: i64[120] = [0; 120],
    head: i32 = 0, count: i32 = 0
}
struct Performance {
    metrics: Metrics = Metrics {}, page: mygoose::ScrollAreaState = mygoose::ScrollAreaState {},
    list: mygoose::ScrollState = mygoose::ScrollState {}, list_bounds: mygoose::Rect = mygoose::Rect {},
    paused: bool = false, light: bool = false, rate: i64 = 1,
    tiles: f32 = 24.0, work_ms: f32 = 0.0, selected: i64 = -1, clicks: i64 = 0,
    spike: bool = false, reset: bool = false, phase: f32 = 0.0, now_ns: i64 = 0,
    checksum: i64 = 1, nodes: i32 = 0, dirty_percent: f32 = 0.0, dirty_node: i32 = -1,
    chart_scales: f32[6] = [90.0, 20.0, 20.0, 100.0, 100.0, 256.0],
    synced: bool = false, display_hz: i32 = 0,
    chart_nodes: i32[6] = [-1; 6], hover_enabled: bool = false, hover_kind: i32 = -1, hover_index: i32 = -1,
    note: mygoose::TextInput = mygoose::TextInput {}
}
fn target(s: Performance&) -> i32 { match s.rate { 0 => 30, 2 => 120, _ => 60 } }
fn effective_target(s: Performance&) -> i32 { if s.synced && s.display_hz > 0 { min(target(s),s.display_hz) } else { target(s) } }
fn period_ns(s: Performance&) -> i64 { 1000000000 / effective_target(s) }
fn reset_metrics(m: Metrics&, now: i64, cpu: i64) { m = Metrics { origin_ns: now, start_ns: now, cpu_start_ns: cpu }; }
fn record(m: Metrics&, now: i64, cpu: i64, build: i64, paint: i64, frame_cpu: i64, presented: bool, active: bool, period: i64) {
    m.builds += 1; m.build_ns += build; m.paint_ns += paint;
    if frame_cpu >= 0 { m.frame_cpu_ns += frame_cpu; }
    if presented {
        if m.last_present_ns > 0 && active {
            let interval = now - m.last_present_ns; m.worst_ns = max(m.worst_ns, interval);
            if interval > period * 3 / 2 { m.late += 1; m.total_late += 1; }
        }
        m.last_present_ns = now; m.frames += 1;
    }
    let elapsed = now - m.start_ns;
    if elapsed < 250000000 { return; }
    m.fps = m.frames * 1000000000.0 / elapsed;
    m.build_ms = m.build_ns / (max(1, m.builds) * 1000000.0);
    m.paint_ms = m.paint_ns / (max(1, m.builds) * 1000000.0);
    m.cpu_ms = if cpu >= 0 && m.cpu_start_ns >= 0 { m.frame_cpu_ns / (max(1, m.builds) * 1000000.0) } else { -1.0 };
    m.cpu_percent = if cpu >= 0 && m.cpu_start_ns >= 0 { (cpu - m.cpu_start_ns) * 100.0 / elapsed } else { -1.0 };
    m.worst_ms = if m.worst_ns > 0 { m.worst_ns / 1000000.0 } else { -1.0 };
    m.begin_history[m.head] = m.start_ns; m.end_history[m.head] = now;
    m.fps_history[m.head] = m.fps; m.cpu_history[m.head] = m.cpu_percent;
    m.build_history[m.head] = m.build_ms; m.paint_history[m.head] = m.paint_ms;
    m.memory_history[m.head] = m.memory_mb; m.interval_history[m.head] = m.worst_ms;
    m.frame_cpu_history[m.head] = m.cpu_ms;
    m.head = (m.head + 1) % history_count; m.count = min(history_count, m.count + 1);
    m.start_ns = now; m.cpu_start_ns = cpu; m.frames = 0; m.builds = 0;
    m.build_ns = 0; m.paint_ns = 0; m.frame_cpu_ns = 0; m.worst_ns = 0; m.late = 0;
}
fn append_decimal(out: u8[>..]&, amount: f32) {
    let tenths = (amount * 10.0 + 0.5) as! i64;
    format(out, tenths / 10); out.push('.'); format(out, tenths % 10);
}
fn value(c: mygoose::Context&, amount: f32, suffix: const u8[:], size: f32 = 26.0, color: u32 = blue) {
    var out: u8[>..] = [];
    if amount < 0.0 { out.append("—"); }
    else { append_decimal(out, amount); }
    out.append(suffix); mygoose::text(c, out, mygoose::TextOptions { size: size, bold: true, color: color });
}
fn muted(c: mygoose::Context&, text: const u8[:], size: f32 = 12.0) {
    mygoose::text(c, text, mygoose::TextOptions { size: size, color: c.theme.muted });
}
fn metric(c: mygoose::Context&, width: f32, label: const u8[:], amount: f32, unit: const u8[:], detail: const u8[:], color: u32) {
    mygoose::column(c, mygoose::Box { width: width, height: 108.0, padding: 16.0, gap: 7.0, background: c.theme.surface, radius: 12.0 }) {
        muted(c, label); value(c, amount, unit, 26.0, color); muted(c, detail, 11.0);
    };
}
fn metric_row(s: Performance&, c: mygoose::Context&, width: f32) {
    let columns: i32 = if width >= 720.0 { 4 } else { 2 };
    let card = (width - (columns - 1) * 12.0) / columns;
    for row: i32 in 4 / columns {
        mygoose::row(c, mygoose::Box { width: width, gap: 12.0 }) {
            for col: i32 in columns {
                let i = row * columns + col;
                match i {
                    0 => { metric(c, card, "UI FRAME RATE", if s.metrics.count > 0 { s.metrics.fps } else { -1.0 }, " fps", "Painted frames / second", blue); },
                    1 => { metric(c, card, "UPDATE CPU TIME", s.metrics.cpu_ms, " ms", "Work + layout + paint", green); },
                    2 => { metric(c, card, "WORST FRAME INTERVAL", s.metrics.worst_ms, " ms", "Latest 250 ms window", amber); },
                    3 => { metric(c, card, "RESIDENT MEMORY", s.metrics.memory_mb, " MiB", "This process", purple); },
                    _ => {},
                }
            }
        };
    }
}
// Both the bar plot and hover read the same history channel.
fn chart_sample(m: Metrics&, kind: i32, index: i32) -> f32 {
    match kind {
        0 => m.fps_history[index],
        1 => m.build_history[index],
        2 => m.frame_cpu_history[index],
        3 => m.cpu_history[index],
        4 => m.interval_history[index],
        _ => m.memory_history[index],
    }
}
fn chart_value(m: Metrics&, kind: i32) -> f32 {
    match kind {
        0 => if m.count > 0 { m.fps } else { -1.0 },
        1 => if m.count > 0 { m.build_ms + m.paint_ms } else { -1.0 },
        2 => m.cpu_ms,
        3 => m.cpu_percent,
        4 => m.worst_ms,
        _ => m.memory_mb,
    }
}
fn chart_card(s: Performance&, c: mygoose::Context&, width: f32, kind: i32) {
    var pairs: f32[..240] = [];
    let minimum_scale = match kind {
        0 => target(s) * 1.25,
        1, 2 => period_ns(s) / 1000000.0,
        _ => 1.0,
    };
    var scale: f32 = max(s.chart_scales[kind], minimum_scale);
    for i: i32 in history_count {
        let index = (s.metrics.head + i) % history_count;
        let first = chart_sample(s.metrics, kind, index);
        let second = if kind == 1 { s.metrics.paint_history[index] } else { -1.0 };
        pairs.push(first); pairs.push(second);
        // Hold the vertical scale between samples; expand in whole steps
        // only when necessary, so old bars keep their measured height.
        let peak = max(0.0, first) + max(0.0, second);
        while peak > scale { scale *= 2.0; }
    }
    s.chart_scales[kind] = scale;
    let palette = mygoose_charts::theme_palette(c.theme);
    mygoose::column(c, mygoose::Box { width: width, padding: 18.0, gap: 10.0, background: c.theme.surface, radius: 12.0 }) {
        mygoose::row(c, mygoose::Box { width: width - 36.0, align: 1 }) {
            mygoose::column(c, mygoose::Box { grow: 1.0 }) { mygoose::text(c, chart_names[kind], mygoose::TextOptions { size: 15.0, bold: true }); };
            value(c, chart_value(s.metrics, kind), chart_units[kind], 17.0, chart_colors[kind]);
        };
        s.chart_nodes[kind] = c.count;
        mygoose_charts::bars(c, width - 36.0, 112.0, pairs, scale, 30,
            mygoose_charts::Options { color: chart_colors[kind], second: blue, palette: palette, key: chart_names[kind] });
        mygoose::row(c, mygoose::Box { width: width - 36.0, gap: 6.0, align: 1 }) {
            mygoose::column(c, mygoose::Box { grow: 1.0 }) {
                let detail = match kind {
                    1 => "Green: layout · Blue: paint",
                    3 => "100% = one CPU core",
                    _ => "250 ms / bar · 30 seconds",
                };
                muted(c, detail, 11.0);
            };
            muted(c, "Top", 10.0);
            value(c, scale, chart_units[kind], 11.0, c.theme.muted);
        };
    };
}
fn controls(s: Performance&, c: mygoose::Context&, width: f32) {
    mygoose::column(c, mygoose::Box { width: width, padding: 18.0, gap: 14.0, background: c.theme.surface, radius: 12.0 }) {
        mygoose::text(c, "Change the workload", mygoose::TextOptions { size: 17.0, bold: true });
        muted(c, "Drag a slider, add a spike, then watch the charts respond.");
        mygoose::row(c, mygoose::Box { width: width - 36.0, gap: 12.0, align: 1 }) {
            muted(c, "CPU work / frame");
            mygoose::slider(c, s.work_ms, 0.0, 12.0, mygoose::SliderOptions { width: max(80.0, width - 330.0), step: 0.5, key: "cpu-work" });
            value(c, s.work_ms, " ms", 15.0, amber);
        };
        mygoose::row(c, mygoose::Box { width: width - 36.0, gap: 12.0, align: 1 }) {
            muted(c, "Animated tiles");
            mygoose::slider(c, s.tiles, 8.0, 96.0, mygoose::SliderOptions { width: max(80.0, width - 330.0), step: 8.0, key: "tile-count" });
            value(c, s.tiles, "", 15.0, blue);
        };
        if width >= 540.0 { mygoose::row(c, mygoose::Box { gap: 10.0, align: 1 }); }
        else { mygoose::column(c, mygoose::Box { gap: 10.0 }); }
        mygoose::select(c, rates, s.rate, mygoose::SelectOptions { width: 158.0, key: "rate" });
        if mygoose::button(c, "+24 ms spike", mygoose::ButtonOptions { key: "spike" }) { s.spike = true; }
        mygoose::toggle(c, "Light", s.light, mygoose::CheckOptions { key: "light" });
        mygoose::end(c);
        mygoose::row(c, mygoose::Box { gap: 12.0, align: 1 }) {
            muted(c, "Current frame budget"); value(c, period_ns(s) / 1000000.0, " ms", 15.0, green);
            muted(c, "Late frames"); mygoose::text_number(c, s.metrics.total_late);
        };
        mygoose::row(c, mygoose::Box { gap: 10.0 }) {
            muted(c, if s.synced { "Display sync" } else { "Timed pacing" });
            if s.display_hz > 0 { mygoose::text_number(c, s.display_hz); muted(c, "Hz display"); }
            if s.synced && s.display_hz > 0 && target(s) > s.display_hz { muted(c, "Frame rate limited by display"); }
        };
    };
}
fn tiles(s: Performance&, c: mygoose::Context&, width: f32) {
    let columns: i32 = if width > 700.0 { 6 } else { if width > 440.0 { 4 } else { 2 } };
    let tile_width = (width - (columns - 1) * 10.0) / columns;
    let count = s.tiles as! i32;
    mygoose::text(c, "Live workload", mygoose::TextOptions { size: 18.0, bold: true });
    muted(c, "Click a tile to select it. Resize the window to reflow the grid.");
    for row: i32 in (count + columns - 1) / columns {
        mygoose::row(c, mygoose::Box { gap: 10.0 }) {
            for col: i32 in columns {
                let i = row * columns + col; if i >= count { break; }
                mygoose::column(c, mygoose::Box { width: tile_width, padding: 10.0, gap: 8.0, background: c.theme.surface, radius: 10.0 }) {
                    var title: u8[>..] = []; title.append("Tile "); format(title, i + 1);
                    if mygoose::button(c, title, mygoose::ButtonOptions { width: tile_width - 20.0, selected: s.selected == i, key: "tile" }) { s.selected = i; s.clicks += 1; }
                    let wave = (s.phase + i * 0.071) % 1.0;
                    mygoose_charts::bar(c, tile_width - 20.0, 5.0, if wave < 0.5 { wave * 2.0 } else { (1.0 - wave) * 2.0 },
                        mygoose_charts::Options { color: if s.selected == i { amber } else { blue }, palette: mygoose_charts::Palette { track: c.theme.border } });
                };
            }
        };
    }
}
fn rows(s: Performance&, c: mygoose::Context&, width: f32) {
    mygoose::text(c, "Scroll + interact", mygoose::TextOptions { size: 18.0, bold: true });
    muted(c, "10,000 virtual rows. The outer page and this list scroll independently.");
    mygoose::text_input(c, s.note, mygoose::InputOptions { width: min(width, 440.0), placeholder: "Type while the workload runs…", key: "note" });
    mygoose::virtual_list(c, s.list, 10000, 30.0, mygoose::Box { width: width, height: 300.0, background: c.theme.surface, radius: 10.0 }, "virtual-rows") { i =>
        mygoose::row(c, mygoose::Box { height: 30.0, padding: 4.0, gap: 12.0, align: 1 }) {
            mygoose::text_number(c, i + 1, mygoose::TextOptions { width: 70.0, color: c.theme.muted });
            mygoose::text(c, "Virtual row", mygoose::TextOptions { width: 100.0 });
            mygoose_charts::bar(c, max(30.0, width - 220.0), 4.0, ((i % 100) + 1) / 100.0,
                mygoose_charts::Options { color: green, palette: mygoose_charts::Palette { track: c.theme.border } });
        };
    };
}
fn view(s: Performance&, c: mygoose::Context&) {
    c.theme = if s.light { mygoose::light_theme() } else { mygoose::Theme {} };
    if !s.light { c.theme.background = 0x11141b; c.theme.surface = 0x1b202b; c.theme.border = 0x30394b; c.theme.muted = 0x94a2b8; }
    let width = max(300.0, c.width - 40.0);
    mygoose::column(c, mygoose::Box { fill: true, padding: 20.0, gap: 16.0, clip: true }) {
        mygoose::row(c, mygoose::Box { width: width, height: 48.0, gap: 8.0, align: 1 }) {
            mygoose::column(c, mygoose::Box { grow: 1.0, gap: 4.0 }) {
                mygoose::text(c, "Performance lab", mygoose::TextOptions { size: 24.0, bold: true });
                mygoose::row(c, mygoose::Box { gap: 10.0, align: 1 }) {
                    muted(c, if s.paused { "Workload paused · charts keep sampling" } else { if s.synced { "LIVE · display sync" } else { "LIVE · timed pacing" } }, 11.0);
                    mygoose_charts::bar(c, 44.0, 3.0, s.phase, mygoose_charts::Options { color: green, palette: mygoose_charts::Palette { track: c.theme.border } });
                };
            };
            if mygoose::button(c, if s.paused { "Resume" } else { "Pause" }, mygoose::ButtonOptions { key: "pause" }) { s.paused = !s.paused; s.metrics.last_present_ns = 0; }
            if mygoose::button(c, "Reset", mygoose::ButtonOptions { key: "reset" }) { s.reset = true; }
        };
        let event = c.event;
        let list_can_scroll = (event.delta < 0.0 && s.list.offset < 299700.0) || (event.delta > 0.0 && s.list.offset > 0.0);
        if event.kind == 4 && list_can_scroll && mygoose::contains(s.list_bounds, c.mouse_x, c.mouse_y) { c.event.kind = 0; }
        mygoose::scroll_area(c, s.page, mygoose::Box { width: width, height: max(80.0, c.height - 104.0) }, mygoose::ScrollAreaOptions { key: "page", gap: 16.0 }) { available =>
            c.event = event;
            metric_row(s, c, available);
            let columns: i32 = if available >= 700.0 { 2 } else { 1 };
            for row: i32 in 6 / columns {
                mygoose::row(c, mygoose::Box { gap: 16.0 }) { for col: i32 in columns { chart_card(s, c, (available - (columns - 1) * 16.0) / columns, row * columns + col); } };
            }
            controls(s, c, available);
            tiles(s, c, available);
            rows(s, c, available);
            mygoose::row(c, mygoose::Box { gap: 10.0 }) {
                muted(c, "Scene nodes"); mygoose::text_number(c, s.nodes);
                muted(c, "Dirty area"); s.dirty_node = c.count; value(c, s.dirty_percent, "%", 13.0, blue);
                muted(c, "Tile clicks"); mygoose::text_number(c, s.clicks);
            };
            mygoose::row(c, mygoose::Box { gap: 10.0 }) { muted(c, "Work checksum"); mygoose::text_number(c, s.checksum); };
            muted(c, "UI FPS counts paints, not display refresh. CPU is process time; layout/paint are wall time.", 11.0);
            muted(c, "Paint includes submission to the window system, not GPU completion. Late = >1.5× target interval.", 11.0);
        };
    };
}
fn remember_list_bounds(s: Performance&, c: mygoose::Context&) {
    let i = mygoose::find_node(c, "virtual-rows");
    s.list_bounds = if i >= 0 { mygoose::intersect(c.nodes[i].rect, c.nodes[i].clip_rect) } else { mygoose::Rect {} };
}
fn append_value(out: u8[>..]&, amount: f32, unit: const u8[:]) {
    if amount < 0.0 { out.append("Unavailable"); return; }
    append_decimal(out, amount); out.append(unit);
}
fn append_time(out: u8[>..]&, ns: i64) {
    let ms = (max(0,ns) + 500000) / 1000000;
    format(out,ms / 1000); out.push('.');
    if ms % 1000 < 100 { out.push('0'); } if ms % 1000 < 10 { out.push('0'); }
    format(out,ms % 1000);
}
// Append scene annotations after layout and before damage. They are ordinary
// clipped, noninteractive leaves, so moving/removing hover repaints old bounds.
fn annotation(c: mygoose::Context&, kind: i32, text: const u8[:], rect: mygoose::Rect, clip: mygoose::Rect, key: const u8[:]) -> i32 {
    let parent = c.parent; c.parent = 0;
    let i = mygoose::add(c,kind,text,key); c.parent = parent;
    c.nodes[i].overlay = true; c.nodes[i].rect = rect; c.nodes[i].clip_rect = clip;
    i
}
fn hover_text(c: mygoose::Context&, text: const u8[:], panel: mygoose::Rect, clip: mygoose::Rect, row: i32, key: const u8[:], color: u32, bold: bool = false) {
    let i = annotation(c,2,text,mygoose::Rect { panel.x + 12.0, panel.y + 9.0 + row * 17.0, panel.w - 24.0, 16.0 },clip,key);
    c.nodes[i].size = 11.0; c.nodes[i].color = color; c.nodes[i].bold = bold;
}
fn inspect_charts(s: Performance&, c: mygoose::Context&) {
    s.hover_kind = -1; s.hover_index = -1;
    if !s.hover_enabled || c.popup != 0 || c.active != 0 { return; }
    for kind: i32 in 6 {
        let node = s.chart_nodes[kind]; if node < 0 || node >= c.count { continue; }
        let r = c.nodes[node].rect; let clip = c.nodes[node].clip_rect;
        let hit = mygoose_charts::bar_hover(r,clip,c.mouse_x,c.mouse_y,history_count);
        if hit.index < 0 { continue; }
        let index = (s.metrics.head + hit.index) % history_count;
        let begin = s.metrics.begin_history[index]; let end = s.metrics.end_history[index];
        if end == 0 { return; } // Leading empty slots have no invented timestamp.
        s.hover_kind = kind; s.hover_index = index;
        let line = annotation(c,9,"",mygoose::Rect { hit.x - 0.5, hit.plot.y, 1.0, hit.plot.h },mygoose::intersect(clip,hit.plot),"hover-guide");
        c.nodes[line].color = c.theme.text;
        let bounds = mygoose::intersect(clip,mygoose::Rect { w: c.width, h: c.height });
        let w = min(280.0,bounds.w - 16.0); let h: f32 = if kind == 1 { 104.0 } else { 87.0 };
        let x = if c.mouse_x + w + 12.0 <= bounds.x + bounds.w - 8.0 { c.mouse_x + 12.0 } else { c.mouse_x - w - 12.0 };
        let y = if c.mouse_y + h + 12.0 <= bounds.y + bounds.h - 8.0 { c.mouse_y + 12.0 } else { c.mouse_y - h - 12.0 };
        let panel = mygoose::Rect { clamp(x,bounds.x + 8.0,max(bounds.x + 8.0,bounds.x + bounds.w - w - 8.0)), clamp(y,bounds.y + 8.0,max(bounds.y + 8.0,bounds.y + bounds.h - h - 8.0)), w, h };
        let border = annotation(c,0,"",panel,bounds,"hover-border"); c.nodes[border].box.background = c.theme.border; c.nodes[border].box.radius = 8.0;
        let body = annotation(c,0,"",mygoose::inset(panel,1.0),bounds,"hover-panel"); c.nodes[body].box.background = c.theme.surface; c.nodes[body].box.radius = 7.0;
        hover_text(c,chart_names[kind],panel,bounds,0,"hover-title",c.theme.text,true);
        var time: u8[>..] = []; time.append("Time +"); append_time(time,begin - s.metrics.origin_ns); time.append("–"); append_time(time,end - s.metrics.origin_ns); time.append(" s");
        hover_text(c,time,panel,bounds,1,"hover-time",c.theme.muted);
        var window: u8[>..] = []; window.append("Window "); append_value(window,(end - begin) / 1000000.0," ms"); window.append(" · ~"); append_value(window,max(0,s.metrics.start_ns - end) / 1000000000.0," s ago");
        hover_text(c,window,panel,bounds,2,"hover-window",c.theme.muted);
        var detail: u8[>..] = [];
        if kind == 1 {
            detail.append("Layout "); append_value(detail,s.metrics.build_history[index]," ms"); detail.append(" · Paint "); append_value(detail,s.metrics.paint_history[index]," ms");
            hover_text(c,detail,panel,bounds,3,"hover-value",green);
            detail.clear(); detail.append("Total "); append_value(detail,s.metrics.build_history[index] + s.metrics.paint_history[index]," ms");
            hover_text(c,detail,panel,bounds,4,"hover-total",blue);
        } else {
            let amount = chart_sample(s.metrics, kind, index);
            append_value(detail,amount,chart_units[kind]); hover_text(c,detail,panel,bounds,3,"hover-value",chart_colors[kind],true);
        }
        return;
    }
}
fn build(s: Performance&, c: mygoose::Context&, width: f32, height: f32) {
    if c.event.kind >= 1 && c.event.kind <= 4 { s.hover_enabled = true; }
    if c.event.kind == 7 { s.hover_enabled = false; }
    mygoose::build_frame(c,s,width,height,view); remember_list_bounds(s,c); inspect_charts(s,c); s.nodes = c.count;
}
fn work(s: Performance&) {
    if s.paused { return; }
    let milliseconds = s.work_ms;
    let extra: i64 = if s.spike { 24000000 } else { 0 }; s.spike = false;
    let until = mygoose::mg_clock_ns() + (milliseconds * 1000000.0) as! i64 + extra;
    var checksum = s.checksum;
    while mygoose::mg_clock_ns() < until {
        for i in 2048 { checksum = (checksum * 1664525 + 1013904223) % 2147483647; }
    }
    s.checksum = checksum;
}
struct FrameCost { build_ns: i64 = 0, paint_ns: i64 = 0, painted: bool = false }
fn render(s: Performance&, c: mygoose::Context&, cache: mygoose::SceneCache&, frame_due: bool, kind: i32) -> FrameCost {
    let paused = s.paused; let input = kind != 0 && kind != 9 && (kind != mygoose::event_animation || paused);
    let start = mygoose::mg_clock_ns();
    // Consume input at its arrival rate, even when active paints are paced.
    if frame_due || input { build(s,c,mygoose::mg_width(),mygoose::mg_height()); }
    let paint_start = mygoose::mg_clock_ns();
    // Pausing stops the workload clock, not interaction. Include transitions
    // in either direction so the Pause/Resume button responds immediately.
    // Never update the damage cache for an intermediate, unpainted scene.
    let repaint = (frame_due || (input && (paused || s.paused))) && mygoose::damage(c,cache);
    if repaint {
        mygoose_charts::paint(c);
        // This footer is normally below the viewport. Keep its diagnostic out
        // of ordinary chart frames until the user scrolls it into view.
        if s.dirty_node >= 0 && s.dirty_node < c.count {
            let node .= c.nodes[s.dirty_node]; let visible = mygoose::intersect(node.rect, node.clip_rect);
            if visible.w > 0.0 && visible.h > 0.0 { s.dirty_percent = mygoose::paint_area(c) * 100.0 / (c.width * c.height); }
        }
    }
    FrameCost { build_ns: paint_start - start, paint_ns: mygoose::mg_clock_ns() - paint_start, painted: repaint }
}
fn run(s: Performance&, benchmark_ns: i64 = 0, display_sync: bool = true, warmup_ns: i64 = 1000000000) {
    assert(mygoose::mg_open("MyGoose Performance", 1000, 760, false));
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    reset_metrics(s.metrics, mygoose::mg_clock_ns(), mygoose::mg_cpu_ns());
    var benchmark_start = mygoose::mg_clock_ns();
    var benchmark_warm = benchmark_ns == 0;
    var benchmark_cpu = mygoose::mg_cpu_ns(); var benchmark_rss_peak: i64 = 0;
    var benchmark_last: i64 = 0; var benchmark_jitter: i64 = 0; var benchmark_worst: i64 = 0; var benchmark_intervals: i64 = 0;
    var benchmark_frames: i64 = 0; var benchmark_build: i64 = 0; var benchmark_paint: i64 = 0; var benchmark_wait: i64 = 0;
    var pacer = mygoose::FramePacer {}; var pending_build: i64 = 0; var pending_cpu: i64 = 0;
    s.synced = display_sync && mygoose::mg_display_sync(target(s)); s.display_hz = mygoose::mg_display_hz();
    var kind: i32 = 0;
    while true {
        let start = mygoose::mg_clock_ns(); let cpu_start = mygoose::mg_cpu_ns(); s.now_ns = start;
        if s.reset { reset_metrics(s.metrics, start, cpu_start); s.chart_scales = [90.0, 20.0, 20.0, 100.0, 100.0, 256.0]; s.reset = false; }
        mygoose::frame_period(pacer, start, if s.paused { 250000000 } else { period_ns(s) });
        let frame_due = (s.synced && kind == 0) || mygoose::frame_tick(pacer,start,kind,s.synced);
        if frame_due && !s.paused { s.phase = (mygoose::mg_frame_time_ns() % 4000000000) / 4000000000.0; }
        mygoose::send_native(c, kind);
        if frame_due { work(s); }
        let cost = render(s,c,cache,frame_due,kind); let repaint = cost.painted;
        if mygoose::mg_dump_requested() { assert(mygoose::mg_dump()); break; }
        let end = mygoose::mg_clock_ns(); let cpu_end = mygoose::mg_cpu_ns();
        pending_build += cost.build_ns;
        if cpu_start >= 0 && cpu_end >= cpu_start { pending_cpu += cpu_end - cpu_start; }
        if repaint {
            benchmark_frames += 1;
            if benchmark_last > 0 {
                let interval = end - benchmark_last;
                benchmark_jitter += abs(interval - period_ns(s)); benchmark_worst = max(benchmark_worst,interval); benchmark_intervals += 1;
            }
            benchmark_last = end;
        }
        benchmark_build += cost.build_ns; benchmark_paint += cost.paint_ns;
        if !benchmark_warm && end - benchmark_start >= warmup_ns {
            benchmark_warm = true; benchmark_start = end; benchmark_frames = 0; benchmark_build = 0; benchmark_paint = 0; benchmark_wait = 0;
            benchmark_jitter = 0; benchmark_worst = 0; benchmark_intervals = 0; benchmark_last = end;
            benchmark_cpu = cpu_end; benchmark_rss_peak = 0;
        }
        if benchmark_ns > 0 { benchmark_rss_peak = max(benchmark_rss_peak,mygoose::mg_memory_bytes()); }
        if benchmark_ns > 0 && benchmark_warm && end - benchmark_start >= benchmark_ns {
            print("target=", target(s), " display_hz=", s.display_hz, " synced=", s.synced, " paints=", benchmark_frames, " elapsed_ns=", end - benchmark_start,
                " fps=", benchmark_frames * 1000000000.0 / (end - benchmark_start),
                " build_ns=", benchmark_build / max(1, benchmark_frames), " paint_ns=", benchmark_paint / max(1, benchmark_frames),
                " wait_ns=", benchmark_wait / max(1, benchmark_frames),
                " cpu_percent=", (cpu_end - benchmark_cpu) * 100.0 / (end - benchmark_start), " rss_bytes=", mygoose::mg_memory_bytes(), " rss_peak_bytes=", benchmark_rss_peak,
                " native_storage_bytes=", mygoose::mg_storage_bytes(),
                " mean_abs_jitter_ns=", benchmark_jitter / max(1,benchmark_intervals), " worst_interval_ns=", benchmark_worst);
            break;
        }
        if frame_due || repaint {
            if end - s.metrics.start_ns >= 250000000 { let memory = mygoose::mg_memory_bytes(); s.metrics.memory_mb = if memory >= 0 { memory / 1048576.0 } else { -1.0 }; }
            record(s.metrics, end, cpu_end, pending_build, cost.paint_ns,
                if cpu_start >= 0 && cpu_end >= cpu_start { pending_cpu } else { -1 }, repaint, !s.paused, period_ns(s));
            pending_build = 0; pending_cpu = 0;
        }
        // An early input paint must not postpone periodic sampling.
        if frame_due {
            mygoose::frame_period(pacer, end, if s.paused { 250000000 } else { period_ns(s) }); mygoose::frame_advance(pacer, end);
        }
        mygoose::frame_period(pacer, mygoose::mg_clock_ns(), if s.paused { 250000000 } else { period_ns(s) });
        s.synced = display_sync && mygoose::mg_display_sync(if s.paused { 0 } else { target(s) }); s.display_hz = mygoose::mg_display_hz();
        let timeout = if s.synced { 0 } else { mygoose::frame_wait_ms(pacer, mygoose::mg_clock_ns()) };
        if !s.synced && timeout == 0 { kind = 0; continue; }
        let wait_start = mygoose::mg_clock_ns();
        kind = mygoose::mg_wait(timeout);
        benchmark_wait += mygoose::mg_clock_ns() - wait_start;
        if kind < 0 { break; }
    }
    mygoose::mg_close();
}
