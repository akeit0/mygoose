import mygoose from "..";
import std;

fn run_scroll_cases() {
    let start: i64 = 1000000000;
    var m = mygoose::ScrollMotion {};
    mygoose::target_scroll(m, 72.0, start);
    assert(abs(mygoose::sample_scroll(m, start + 100000000) - 36.0) < 0.001);
    let position = m.value; let velocity = m.velocity;
    mygoose::target_scroll(m, 144.0, start + 100000000);
    assert(abs(m.value - position) < 0.000001);
    mygoose::sample_scroll(m, start + 100000000);
    assert(abs(m.velocity - velocity) < 0.001);
    let end = m.start_ns + m.duration_ns;
    mygoose::target_scroll(m, 144.0, start + 110000000);
    assert(m.start_ns + m.duration_ns == end); // No slowdown at an unchanged limit.
    assert(mygoose::sample_scroll(m, end + 1000000000) == 144.0 && !m.active);

    // Sample every rendered frame while 1,000 pointer events/second arrive.
    // Retarget every 50 ms. Neither event count nor 30/60/120 Hz paint pacing
    // may produce a frozen frame or lose any of the 40 wheel notches.
    for hz in [30, 60, 120] {
        var c = mygoose::Context {};
        var offset: f32 = 0.0; var painted: f32 = 0.0;
        var next_frame: i64 = 0; var frames: i64 = 0;
        for tick in 2000 {
            let now = start + tick * 1000000; c.frame_ns = now;
            mygoose::send(c, mygoose::Event { kind: if tick % 50 == 0 { 4 } else { 1 },
                x: 20.0 + tick % 3, y: 20.0, delta: -1.0, scroll_smooth: true });
            offset = mygoose::scroll_offset(c, 42, offset, 100000.0, 72.0, true);
            if tick * 1000000 >= next_frame {
                // Render-only frames advance without receiving another wheel.
                mygoose::send(c, mygoose::Event {});
                offset = mygoose::scroll_offset(c, 42, offset, 100000.0, 72.0, true);
                if tick > 200 { assert(offset > painted); }
                painted = offset; next_frame += 1000000000 / hz; frames += 1;
            }
        }
        c.frame_ns = start + 3000000000;
        mygoose::send(c, mygoose::Event {});
        offset = mygoose::scroll_offset(c, 42, offset, 100000.0, 72.0, false);
        assert(offset == 2880.0 && c.scroll_owner == 0 && frames >= hz * 2);
    }

    var c = mygoose::Context { frame_ns: start };
    mygoose::send(c, mygoose::Event { kind: 4, delta: -10.0, scroll_smooth: true });
    var offset = mygoose::scroll_offset(c, 42, 0.0, 100.0, 72.0, true);
    assert(c.scroll.target == 100.0);
    c.frame_ns += 80000000;
    mygoose::send(c, mygoose::Event { kind: 1, x: 500.0, y: 600.0 });
    offset = mygoose::scroll_offset(c, 42, offset, 100.0, 72.0, false);
    assert(offset > 0.0 && offset < 100.0 && c.scroll_owner == 42);
    // Reversal heads toward the new direction rather than spending old debt.
    mygoose::send(c, mygoose::Event { kind: 4, delta: 1.0, scroll_smooth: true });
    offset = mygoose::scroll_offset(c, 42, offset, 100.0, 72.0, true);
    assert(c.scroll.target == 0.0 && c.scroll.velocity == 0.0);
    c.frame_ns += 30000000;
    mygoose::send(c, mygoose::Event {});
    let previous = offset;
    offset = mygoose::scroll_offset(c, 42, offset, 100.0, 72.0, false);
    assert(offset < previous);
    // A scrollbar drag or programmatic reveal wins over an old animation.
    assert(mygoose::scroll_offset(c, 42, 75.0, 100.0, 72.0, false) == 75.0 && c.scroll_owner == 0);
    mygoose::send(c, mygoose::Event { kind: 4, delta: -1.0, scroll_smooth: true });
    offset = mygoose::scroll_offset(c, 42, 0.0, 100.0, 72.0, true);
    mygoose::send(c, mygoose::Event { kind: 4, delta: -0.25, scroll_pixels: true });
    assert(mygoose::scroll_offset(c, 42, offset, 100.0, 72.0, true) == 0.25 && c.scroll_owner == 0);
    print("PASS: scroll destination/velocity continuity, unchanged limits, exact distance, 30/60/120 Hz frames under pointer flood, reversal and direct input/offset overrides\n");
}
