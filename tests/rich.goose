import .test_support;
import mygoose from "../src";
import mygoose_graphics from "../extras/graphics";
import mygoose_motion from "../extras/motion";
import mygoose_motion_app from "../extras/motion/app";
import std;

fn near(a: f32, b: f32, eps: f32 = 0.001) { assert(abs(a - b) <= eps); }
fn motion_cases() {
    var f = mygoose_motion::Frame {}; var t = mygoose_motion::Tween {};
    near(mygoose_motion::tween(t, f, 0.0), 0.0); assert(!f.active);
    near(mygoose_motion::tween(t, f, 100.0, 1000.0), 0.0); assert(f.active);
    f.now_ns = 500000000; f.active = false; near(mygoose_motion::tween(t, f, 100.0, 1000.0), 50.0);
    // Same logical frame can be built twice without advancing motion twice.
    near(mygoose_motion::tween(t, f, 100.0, 1000.0), 50.0);
    near(mygoose_motion::tween(t, f, -50.0, 1000.0), 50.0);
    f.now_ns = 1000000000; near(mygoose_motion::tween(t, f, -50.0, 1000.0), 0.0);
    f.now_ns = 1500000000; f.active = false; near(mygoose_motion::tween(t, f, -50.0, 1000.0), -50.0); assert(!f.active);
    f.reduced = true; f.active = false; near(mygoose_motion::tween(t, f, 250.0), 250.0); assert(!f.active);
    f.reduced = false; near(mygoose_motion::tween(t, f, 250.0), 250.0); assert(!f.active);
    near(mygoose_motion::tween(t, f, 10.0, 0.0), 10.0);
    var custom = mygoose_motion::Tween {}; f = mygoose_motion::Frame {};
    mygoose_motion::tween(custom, f, 0.0, 1000.0, mygoose_motion::linear);
    mygoose_motion::tween(custom, f, 100.0, 1000.0, mygoose_motion::linear);
    f.now_ns = 250000000; near(mygoose_motion::tween(custom, f, 100.0, 1000.0, mygoose_motion::linear), 25.0);
    for damping in 3 {
        let ratio: f32 = if damping == 0 { 0.6 } else { if damping == 1 { 1.0 } else { 1.8 } };
        var a = mygoose_motion::Spring {}; var b = mygoose_motion::Spring {};
        f = mygoose_motion::Frame {};
        mygoose_motion::spring(a, f, 0.0, 3.0, ratio); mygoose_motion::spring(b, f, 0.0, 3.0, ratio);
        mygoose_motion::spring(a, f, 100.0, 3.0, ratio); mygoose_motion::spring(b, f, 100.0, 3.0, ratio);
        f.now_ns = 250000000; mygoose_motion::spring(a, f, 100.0, 3.0, ratio);
        for i in 25 { f.now_ns = (i + 1) * 10000000; mygoose_motion::spring(b, f, 100.0, 3.0, ratio); }
        near(a.value, b.value, 0.01); near(a.velocity, b.velocity, 0.01);
        let before = a.value; let velocity = a.velocity;
        mygoose_motion::spring(a, f, -100.0, 3.0, ratio); near(a.value, before); near(a.velocity, velocity);
        f.now_ns = 10000000000; f.active = false; near(mygoose_motion::spring(a, f, -100.0, 3.0, ratio), -100.0); assert(!f.active);
        f.reduced = true; f.active = false; near(mygoose_motion::spring(a, f, 200.0), 200.0); assert(!f.active && a.velocity == 0.0);
    }
    print("PASS: tween retargeting, spring damping/velocity, frame-rate independence, settling and reduced motion");
}
struct RichState { x: f32 = 55.0, angle: f32 = 0.0, alpha: f32 = 0.5, show: bool = true, selected: i64 = 0 }
let options: const u8[:][2] = ["One", "Two"];
fn rich_view(s: RichState&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 12.0, gap: 8.0 }) {
        mygoose::select(c, options, s.selected, mygoose::SelectOptions { key: "select" });
        if s.show {
            var command_count = 0;
            mygoose_graphics::canvas(c, 320.0, 210.0, "canvas") { p =>
                mygoose_graphics::rect(p, 0.0, 0.0, 320.0, 210.0, mygoose_graphics::Brush { color: 0x2a2a30 }, 12.0);
                mygoose_graphics::circle(p, s.x, 70.0, 35.0, mygoose_graphics::Brush { color: 0xff2020, opacity: s.alpha });
                mygoose_graphics::translate(p, s.x, 140.0) {
                    mygoose_graphics::rotate(p, s.angle) {
                        mygoose_graphics::scale(p, 1.2) {
                            mygoose_graphics::opacity(p, 0.6) {
                                mygoose_graphics::rect(p, -25.0, -15.0, 50.0, 30.0, mygoose_graphics::Brush { color: 0x3b82f6 }, 4.0);
                            };
                        };
                    };
                };
                var path = mygoose_graphics::Path {}; mygoose_graphics::move_to(path, 10.0, 190.0);
                mygoose_graphics::quad_to(path, 90.0, 30.0, 150.0, 120.0);
                mygoose_graphics::cubic_to(path, 180.0, 180.0, 260.0, 20.0, 310.0, 190.0);
                mygoose_graphics::draw_path(p, path, mygoose_graphics::Brush { color: 0x10ee99, width: 3.0 });
                // Canvas clipping contains shapes outside the leaf's bounds.
                mygoose_graphics::circle(p, 320.0, 210.0, 30.0, mygoose_graphics::Brush { color: 0xff00ff, opacity: 0.5 });
                command_count = p.commands.len;
                near(p.transform.a, 1.0); near(p.transform.x, 0.0); near(p.opacity, 1.0);
            };
            assert(command_count > 0); // Default trailing-block painter is a reference.
        }
        mygoose::text(c, "After canvas");
    };
}
fn frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: RichState&) {
    mygoose::build_frame(c, s, 400.0, 300.0, rich_view);
    test_support::paint_checked(c, cache, mygoose_graphics::paint);
}
fn main() {
    motion_cases(); mygoose::headless_open(400, 300);
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {}; var s = RichState {};
    frame(c, cache, s); let first = mygoose::mg_pixel_hash(); assert(!mygoose::damage(c, cache));
    // Decorative canvas content is not a focus or pointer target.
    let canvas = mygoose::find(c, "canvas");
    assert(mygoose::hit(c, canvas.x + canvas.w * 0.5, canvas.y + canvas.h * 0.5) == 0);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_tab }); frame(c, cache, s);
    let select_focus = c.focus;
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_tab }); frame(c, cache, s);
    assert(c.focus == select_focus && select_focus != 0);
    for i in 12 {
        s.x = 60.0 + i * 18.0; s.angle = i * 0.2; s.alpha = 0.1 + i * 0.05;
        frame(c, cache, s); assert(mygoose::mg_pixel_hash() != first);
    }
    mygoose::click(c, s, "select", rich_view); assert(c.popup != 0); frame(c, cache, s);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape }); frame(c, cache, s);
    s.show = false; frame(c, cache, s); assert(!mygoose::damage(c, cache));
    s.show = true; frame(c, cache, s);
    mygoose::mg_close(); print("PASS: optional canvas paths, transforms, alpha, clipping, popup layering and partial/full pixel equality");
}
