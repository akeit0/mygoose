import mygoose from "../src";
import std;

fn animation_clocks() {
    var clock = mygoose::AnimationClock {};
    assert(mygoose::animation_elapsed_ns(clock, 100) == 0);
    assert(mygoose::animation_elapsed_ns(clock, 120) == 20);
    assert(mygoose::animation_elapsed_ns(clock, 120) == 20); // Rebuild, same sample.
    assert(mygoose::animation_elapsed_ns(clock, 110) == 20); // Input before predicted frame time.
    assert(mygoose::animation_elapsed_ns(clock, 130) == 30);
    assert(mygoose::animation_elapsed_ns(clock, 200, true) == 30);
    assert(mygoose::animation_elapsed_ns(clock, 300, true) == 30);
    assert(mygoose::animation_elapsed_ns(clock, 310) == 40); // No paused-time jump.
    for hz in [30, 60, 120] {
        var sampled = mygoose::AnimationClock {};
        for i in 0..hz + 1 {
            let time = i * 1000000000 / hz;
            let elapsed = mygoose::animation_elapsed_ns(sampled, time);
            assert(elapsed == time && mygoose::animation_elapsed_ns(sampled, time) == time);
        }
        assert(sampled.elapsed_ns == 1000000000);
    }
    print("PASS: frame-rate-independent animation clock, rebuild/backward timestamps, pause and resume\n");
}
fn pacing() {
    for hz in [30,60,120] {
        var p = mygoose::FramePacer {}; let period = 1000000000 / hz;
        mygoose::frame_period(p, 0, period);
        var frames: i64 = 0;
        // 1,000 input updates/second cannot increase the selected paint rate.
        for tick in 5000 {
            let now = tick * 1000000;
            mygoose::frame_period(p, now, period);
            if mygoose::frame_due(p, now) { frames += 1; mygoose::frame_advance(p, now + 1000000); }
        }
        assert(frames >= hz * 5 - 1 && frames <= hz * 5 + 1);
        let deadline = p.next_ns;
        for event in 100 { mygoose::frame_period(p, deadline - 1000, period); assert(p.next_ns == deadline); }
        assert(!mygoose::frame_due(p, deadline - 1) && mygoose::frame_wait_ms(p, deadline - 1) == 1);
        assert(mygoose::frame_due(p, deadline) && mygoose::frame_wait_ms(p, deadline) == 0);
        mygoose::frame_advance(p, deadline + period * 4);
        assert(p.next_ns > deadline + period * 4); // No catch-up paints after a stall.
    }
    for hz in [30,60] {
        var p = mygoose::FramePacer {}; let period = 1000000000 / hz;
        mygoose::frame_period(p, 0, period);
        var now: i64 = 0; var frames: i64 = 0;
        // A late native wait must not add a fresh 6 ms error every frame.
        while now < 5000000000 {
            if mygoose::frame_due(p, now) { frames += 1; now += 2000000; mygoose::frame_advance(p, now); }
            now += mygoose::frame_wait_ms(p, now) * 1000000 + 6000000;
        }
        assert(frames >= hz * 5 - 1 && frames <= hz * 5 + 1);
    }
    var changed = mygoose::FramePacer {};
    mygoose::frame_period(changed, 100, 1000000000);
    mygoose::frame_advance(changed, 100);
    mygoose::frame_period(changed, 200, 8333333);
    assert(changed.next_ns == 8333533); // Faster target responds within its new interval.
    let next = changed.next_ns;
    mygoose::frame_period(changed, 300, 33333333);
    assert(changed.next_ns == next); // Slower target preserves the pending frame.
    mygoose::frame_advance(changed, next);
    assert(changed.next_ns == next + 33333333);
    assert(mygoose::frame_rate(16666667) == 60 && mygoose::frame_rate(8333333) == 120);
    assert(mygoose::frame_rate(33333333) == 30 && mygoose::frame_rate(2000000000) == 1);
    // An input flood never supplies a display tick. Conversely, callbacks
    // just before a CPU deadline must still paint, without a second gate.
    for hz in [30,60,120] {
        var synced = mygoose::FramePacer {}; let period = 1000000000 / hz;
        mygoose::frame_period(synced,0,period);
        for frame in 300 {
            let now = frame * period - 500000;
            for event in 20 { assert(!mygoose::frame_tick(synced,now + event,1,true)); }
            assert(mygoose::frame_tick(synced,now,mygoose::event_frame,true));
            for kind in [9,10,11,12,13,14] { assert(!mygoose::frame_tick(synced,now,kind as! i32,true)); }
            mygoose::frame_advance(synced,now);
        }
    }
    print("PASS: absolute frame deadlines, 30/60/120 FPS under input flood, native-wait overshoot, display ticks without double gating and no catch-up bursts\n");
}

struct PacedInput { clicks: i64 = 0 }
fn paced_view(s: PacedInput&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true }) {
        if mygoose::button(c, "Click", mygoose::ButtonOptions { key: "click" }) { s.clicks += 1; }
        mygoose::text_number(c, s.clicks);
    };
}
fn paced_input() {
    mygoose::headless_open(200,150);
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {}; var s = PacedInput {};
    mygoose::build_frame(c,s,200.0,150.0,paced_view);
    assert(mygoose::damage(c,cache)); mygoose::paint(c);
    let before = mygoose::mg_pixel_hash(); let button = mygoose::find(c,"click");
    // Multiple inputs between two paints must retain both click semantics
    // and damage relative to the last painted scene.
    mygoose::send(c, mygoose::Event { kind: 2, x: button.x + 5.0, y: button.y + 5.0 });
    mygoose::build_frame(c,s,200.0,150.0,paced_view);
    mygoose::send(c, mygoose::Event { kind: 3, x: button.x + 5.0, y: button.y + 5.0 });
    mygoose::build_frame(c,s,200.0,150.0,paced_view);
    assert(s.clicks == 1 && mygoose::mg_pixel_hash() == before);
    assert(mygoose::damage(c,cache)); mygoose::paint(c); let partial = mygoose::mg_pixel_hash();
    assert(partial != before); c.force = true; assert(mygoose::damage(c,cache)); mygoose::paint(c);
    assert(mygoose::mg_pixel_hash() == partial);
    mygoose::mg_close();
    print("PASS: input-only builds retain clicks and damage until the paced paint, partial/full pixels\n");
}
