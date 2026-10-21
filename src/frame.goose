namespace mygoose;
import std;

// When supported, mg_wait delivers event 15 on the main thread at the
// window display's cadence. Zero disables sync; unsupported backends return
// false so callers keep using absolute timed deadlines.
let event_frame: i32 = 15;
extern fn mg_display_sync(fps: i32) -> bool;
extern fn mg_display_hz() -> i32;
// Sample animation at the upcoming presentation time on event_frame. Duration
// measurements must continue to use mg_clock_ns, not this predictive clock.
extern fn mg_frame_time_ns() -> i64;
fn frame_rate(period_ns: i64) -> i32 { assert(period_ns > 0); min(1000, max(1, (1000000000 + period_ns / 2) / period_ns)) as! i32 }

// Caller-owned animation time. Repeated/backward timestamps add no time;
// paused updates advance the timestamp without advancing elapsed animation.
struct AnimationClock { last_ns: i64 = -1, elapsed_ns: i64 = 0 }
fn animation_elapsed_ns(clock: AnimationClock&, now_ns: i64, paused: bool = false) -> i64 {
    assert(now_ns >= 0);
    if clock.last_ns >= 0 && !paused { clock.elapsed_ns += max(0, now_ns - clock.last_ns); }
    clock.last_ns = max(clock.last_ns, now_ns); clock.elapsed_ns
}
fn animation_elapsed_ns(clock: AnimationClock&, paused: bool = false) -> i64 {
    animation_elapsed_ns(clock, mg_frame_time_ns(), paused)
}

// Monotonic absolute deadlines for custom animation loops. Input updates do
// not restart the clock; late frames skip missed slots without catch-up work.
struct FramePacer { next_ns: i64 = 0, period_ns: i64 = 0 }
fn frame_period(p: FramePacer&, now: i64, period: i64) {
    assert(period > 0);
    if p.period_ns == 0 { p.next_ns = now; }
    else { if p.period_ns != period { p.next_ns = min(p.next_ns, now + period); } }
    p.period_ns = period;
}
fn frame_due(p: FramePacer&, now: i64) -> bool { now >= p.next_ns }
fn frame_advance(p: FramePacer&, now: i64) {
    // Keep the original time grid rather than adding a relative sleep after
    // each update. Skip missed slots instead of rendering a catch-up burst.
    assert(p.period_ns > 0);
    p.next_ns += p.period_ns;
    if p.next_ns <= now { p.next_ns += ((now - p.next_ns) / p.period_ns + 1) * p.period_ns; }
}
// A zero result means render now; do not pass it to mg_wait (zero blocks).
fn frame_wait_ms(p: FramePacer&, now: i64) -> i32 {
    if frame_due(p, now) { return 0; }
    min(2147483647, (p.next_ns - now + 999999) / 1000000) as! i32
}

// Display callbacks are already the frame clock. Applying the independent
// CPU deadline a second time would drop callbacks that arrive slightly early.
fn frame_tick(p: FramePacer&, now: i64, kind: i32, synced: bool) -> bool {
    if synced { kind == event_frame } else { frame_due(p,now) }
}
