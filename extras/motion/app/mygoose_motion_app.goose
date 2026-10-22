namespace mygoose_motion_app;
import mygoose from "../../..";
import mygoose_motion from "..";
import std;

// Scheduling is separate from vector rendering, so motion-only UIs do not
// link a vector backend. Both View and Paint are compile-time entities.
fn run<T, View>(state: T&, options: mygoose::WindowOptions = mygoose::WindowOptions {}, reduced_motion: bool = false) {
    run(state, options, reduced_motion, View, mygoose::paint);
}
fn run<T, View, Paint>(state: T&, options: mygoose::WindowOptions = mygoose::WindowOptions {}, reduced_motion: bool = false) {
    assert(options.width > 0 && options.height > 0);
    assert(mygoose::mg_open(options.title, options.width, options.height, false));
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    var frame = mygoose_motion::Frame { reduced: reduced_motion };
    if !options.dark { c.theme = mygoose::light_theme(); }
    var kind: i32 = 0; var pacer = mygoose::FramePacer {}; var pacing = false; var synced = false;
    while true {
        let tick = !pacing || mygoose::frame_tick(pacer, mygoose::mg_clock_ns(), kind, synced);
        mygoose::send_native(c, kind);
        frame.now_ns = max(frame.now_ns, mygoose::mg_frame_time_ns()); frame.active = false;
        mygoose::build_frame(c, state, mygoose::mg_width(), mygoose::mg_height()) { s, context => View(s, context, frame); };
        if (tick || kind == 8) && mygoose::damage(c, cache) { Paint(c); }
        if mygoose::mg_dump_requested() { assert(mygoose::mg_dump()); break; }
        let interval = if frame.active && !frame.reduced { if options.animate_ms > 0 { min(16, options.animate_ms) } else { 16 } } else { options.animate_ms };
        // Keep the pending final frame scheduled if an input-only build
        // finishes a transition before its paint deadline.
        if interval > 0 {
            mygoose::frame_period(pacer, mygoose::mg_clock_ns(), interval as! i64 * 1000000); pacing = true;
        } else { if tick { pacing = false; pacer = mygoose::FramePacer {}; } }
        if tick && pacing { mygoose::frame_advance(pacer, mygoose::mg_clock_ns()); }
        synced = options.display_sync && mygoose::mg_display_sync(if pacing { mygoose::frame_rate(pacer.period_ns) } else { 0 });
        let wait = if pacing && !synced { mygoose::frame_wait_ms(pacer, mygoose::mg_clock_ns()) } else { 0 };
        kind = if pacing && !synced && wait == 0 { 0 } else { mygoose::mg_wait(wait) };
        if kind < 0 { break; }
    }
    mygoose::mg_close();
}
