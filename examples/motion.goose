import mygoose from "../src";
import mygoose_motion from "../extras/motion";
import mygoose_motion_app from "../extras/motion/app";

struct Motion {
    expanded: bool = false, reduced: bool = false,
    amount: mygoose_motion::Tween = mygoose_motion::Tween {}
}
fn view(s: Motion&, c: mygoose::Context&, f: mygoose_motion::Frame&) {
    mygoose::column(c, mygoose::Box { fill: true, center: true, gap: 18.0 }) {
        mygoose::text(c, "Motion without vectors", mygoose::TextOptions { size: 24.0, bold: true });
        if mygoose::button(c, "Change target", mygoose::ButtonOptions { primary: true, key: "change" }) { s.expanded = !s.expanded; }
        mygoose::checkbox(c, "Reduced motion", s.reduced, mygoose::CheckOptions { key: "reduced" });
        f.reduced = s.reduced;
        let amount = mygoose_motion::tween(s.amount, f, if s.expanded { 1.0 } else { 0.1 }, 500.0);
        mygoose::progress(c, amount, 280.0);
    };
}
fn main() {
    var state = Motion {};
    mygoose_motion_app::run(state, mygoose::WindowOptions { title: "MyGoose Motion", width: 400, height: 300 }, view);
}
