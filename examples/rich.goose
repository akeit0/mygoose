import mygoose from "..";
import mygoose_graphics from "../extras/graphics";
import mygoose_motion from "../extras/motion";
import mygoose_motion_app from "../extras/motion/app";
import math;

struct Rich {
    expanded: bool = false, reduced: bool = false,
    position: mygoose_motion::Spring = mygoose_motion::Spring {},
    fade: mygoose_motion::Tween = mygoose_motion::Tween {},
    rotation: mygoose_motion::Spring = mygoose_motion::Spring {}
}
fn view(s: Rich&, c: mygoose::Context&, frame: mygoose_motion::Frame&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 24.0, gap: 16.0 }) {
        mygoose::text(c, "Shapes + motion", mygoose::TextOptions { size: 28.0, bold: true });
        mygoose::text(c, "Paths, opacity and transforms. Springs preserve velocity when interrupted.", mygoose::TextOptions { color: c.theme.muted });
        mygoose::row(c, mygoose::Box { gap: 20.0, align: 1 }) {
            if mygoose::button(c, if s.expanded { "Return" } else { "Animate" }, mygoose::ButtonOptions { primary: true, key: "animate" }) { s.expanded = !s.expanded; }
            mygoose::checkbox(c, "Reduced motion", s.reduced, mygoose::CheckOptions { key: "reduced" });
        };
        frame.reduced = s.reduced;
        let x = mygoose_motion::spring(s.position, frame, if s.expanded { 470.0 } else { 90.0 });
        let angle = mygoose_motion::spring(s.rotation, frame, if s.expanded { 3.1415927 } else { 0.0 });
        let alpha = mygoose_motion::tween(s.fade, frame, if s.expanded { 1.0 } else { 0.35 }, 350.0);
        mygoose_graphics::canvas(c, 592.0, 250.0, "scene") { p =>
            mygoose_graphics::rect(p, 0.0, 0.0, 592.0, 250.0, mygoose_graphics::Brush { color: c.theme.surface }, 12.0);
            for i in 6 { mygoose_graphics::line(p, 32.0 + i * 100.0, 20.0, 32.0 + i * 100.0, 230.0, mygoose_graphics::Brush { color: 0x52525b, opacity: 0.3 }); }
            var curve = mygoose_graphics::Path {};
            mygoose_graphics::move_to(curve, 30.0, 190.0);
            mygoose_graphics::cubic_to(curve, 130.0, 260.0, 180.0, 40.0, 300.0, 120.0);
            mygoose_graphics::quad_to(curve, 440.0, 220.0, 560.0, 70.0);
            mygoose_graphics::draw_path(p, curve, mygoose_graphics::Brush { color: 0x34d399, width: 3.0, opacity: 0.8 });
            mygoose_graphics::circle(p, x, 100.0, 40.0, mygoose_graphics::Brush { color: 0x3b82f6, opacity: alpha });
            mygoose_graphics::circle(p, x, 100.0, 48.0, mygoose_graphics::Brush { color: 0x93c5fd, width: 2.0, opacity: alpha });
            mygoose_graphics::translate(p, x, 100.0) {
                mygoose_graphics::rotate(p, angle) {
                    var arrow = mygoose_graphics::Path {};
                    mygoose_graphics::move_to(arrow, -12.0, -15.0); mygoose_graphics::line_to(arrow, 16.0, 0.0);
                    mygoose_graphics::line_to(arrow, -12.0, 15.0); mygoose_graphics::close(arrow);
                    mygoose_graphics::draw_path(p, arrow, mygoose_graphics::Brush { color: 0xffffff });
                };
            };
        };
        mygoose::text(c, "Click Animate repeatedly to interrupt. The event loop sleeps when motion settles.", mygoose::TextOptions { color: c.theme.muted });
    };
}
fn main() {
    var s = Rich {};
    mygoose_motion_app::run(s, mygoose::WindowOptions { title: "MyGoose Shapes + Motion", width: 640, height: 460 }, view, mygoose_graphics::paint);
}
