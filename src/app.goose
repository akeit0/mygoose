namespace mygoose;
import ui;
import scene;
import frame;

struct WindowOptions { title: const u8[:] = "MyGoose", width: i32 = 640, height: i32 = 480, dark: bool = true, animate_ms: i32 = 0, display_sync: bool = true }
extern fn mg_open(title: const u8[:], width: i32, height: i32, headless: bool) -> bool;
extern fn mg_close();
extern fn mg_wait(timeout_ms: i32) -> i32;
extern fn mg_event_x() -> f32;
extern fn mg_event_y() -> f32;
extern fn mg_event_code() -> i32;
extern fn mg_event_delta() -> f32;
extern fn mg_event_scroll_pixels() -> bool;
extern fn mg_event_mods() -> i32;
extern fn mg_width() -> f32;
extern fn mg_height() -> f32;
extern fn mg_dump_requested() -> bool;
extern fn mg_dump() -> bool;
extern fn mg_clock_ns() -> i64;
extern fn mg_cpu_ns() -> i64;
extern fn mg_memory_bytes() -> i64;
extern fn mg_storage_bytes() -> i64;
extern fn mg_pixel_hash() -> u64;
extern fn mg_renderer() -> i32;
extern fn mg_ime_read(out: u8[:], result: bool) -> i64;
extern fn mg_ime_cursor() -> i32;
extern fn mg_ime_target_start() -> i32;
extern fn mg_ime_target_end() -> i32;

// Consume the current native event before the next mg_wait overwrites it.
// Custom loops share resize invalidation, modifiers, precise scrolling and IME.
fn send_native(c: Context&, kind: i32) {
    assert(kind >= 0);
    if kind == 8 { c.force = true; c.widths = [WidthEntry {}; 512]; }
    match kind {
        10, 11 => {
            var bytes: u8[4096] = [0; 4096]; let length = mg_ime_read(bytes, kind == 11);
            composition(c, bytes[..length], mg_ime_cursor(), mg_ime_target_start(), mg_ime_target_end(), kind == 11);
        },
        _ => {
            let mods = mg_event_mods();
            send(c, Event { kind: kind, x: mg_event_x(), y: mg_event_y(), code: mg_event_code(),
                delta: mg_event_delta(), shift: (mods & 1) != 0, ctrl: (mods & 2) != 0, scroll_pixels: mg_event_scroll_pixels() });
        },
    }
}

fn run<T, View>(state: T&, options: WindowOptions = WindowOptions {}) {
    run(state, options, View, paint);
}
// Optional painters specialize at compile time; the basic run keeps the same
// storage and direct calls, with no runtime function pointer or registry.
fn run<T, View, Paint>(state: T&, options: WindowOptions = WindowOptions {}) {
    assert(options.width > 0 && options.height > 0);
    assert(mg_open(options.title, options.width, options.height, false));
    var c = Context {}; var cache = SceneCache {};
    if !options.dark { c.theme = light_theme(); }
    var pacer = FramePacer {};
    let synced = options.display_sync && options.animate_ms > 0 && mg_display_sync(frame_rate(options.animate_ms as! i64 * 1000000));
    if options.animate_ms > 0 { frame_period(pacer, mg_clock_ns(), options.animate_ms as! i64 * 1000000); }
    build_frame(c, state, mg_width(), mg_height(), View);
    if damage(c, cache) { Paint(c); }
    if mg_dump_requested() { assert(mg_dump()); mg_close(); return; }
    if options.animate_ms > 0 { frame_advance(pacer, mg_clock_ns()); }
    while true {
        let wait = if !synced && options.animate_ms > 0 { frame_wait_ms(pacer, mg_clock_ns()) } else { 0 };
        let kind = if !synced && options.animate_ms > 0 && wait == 0 { 0 } else { mg_wait(wait) };
        if kind < 0 { break; }
        let tick = options.animate_ms <= 0 || frame_tick(pacer, mg_clock_ns(), kind, synced);
        if !tick && (kind == 0 || kind == 9) { continue; }
        send_native(c, kind);
        build_frame(c, state, mg_width(), mg_height(), View);
        // Input is consumed immediately; cache only frames actually painted.
        // Native geometry changes must repaint while AppKit is suspended.
        if (tick || kind == 8) && damage(c, cache) { Paint(c); }
        if tick && options.animate_ms > 0 { frame_advance(pacer, mg_clock_ns()); }
    }
    mg_close();
}

// Headless tests use exactly the same layout, input, scene and CPU renderer.
fn headless_open(width: i32, height: i32) { assert(mg_open("MyGoose headless", width, height, true)); }
// Explicit keys are scoped to their parent container. An unkeyed node's
// positional ID can equal a key hash; only explicit keys participate here.
fn find_node(c: Context&, key: const u8[:]) -> i32 {
    if key.len == 0 { return -1; }
    for i: i32 in c.count {
        let n .= c.nodes[i]; if !n.keyed { continue; }
        let seed = if n.parent >= 0 { c.nodes[n.parent].id } else { 14695981039346656037 };
        if hash_text(key, seed) == n.id { return i; }
    }
    -1
}
fn find(c: Context&, key: const u8[:]) -> Rect {
    let i = find_node(c, key); assert(i >= 0); c.nodes[i].rect
}
fn click<T, View>(c: Context&, state: T&, key: const u8[:]) {
    let r = find(c, key); let x = r.x + r.w * 0.5; let y = r.y + r.h * 0.5;
    send(c, Event { kind: 2, x: x, y: y }); build_frame(c, state, c.width, c.height, View);
    send(c, Event { kind: 3, x: x, y: y }); build_frame(c, state, c.width, c.height, View);
}
