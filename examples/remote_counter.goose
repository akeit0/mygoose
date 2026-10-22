// Copy this file into another directory and build it with an installed Goose:
//   goose build remote_counter.goose --cc gcc
// Use --cc clang on macOS. CMake and the platform dependencies are required;
// Goose fetches MyGoose automatically. Pin a commit instead of main for reproducibility.
import mygoose from "github.com/akeit0/mygoose@main";

struct Counter { n: i64 = 0 }
fn view(s: Counter&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, center: true, gap: 16.0 }) {
        mygoose::text_number(c, s.n, mygoose::TextOptions { size: 56.0, bold: true });
        if mygoose::button(c, "Increment", mygoose::ButtonOptions { primary: true }) { s.n += 1; }
    };
}
fn main() {
    var state = Counter {};
    mygoose::run(state, mygoose::WindowOptions { title: "Counter", width: 360, height: 280 }, view);
}
