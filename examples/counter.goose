import mygoose from "..";
struct Counter { n: i64 = 0 }
fn view(s: Counter&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, center: true, gap: 16.0 }) {
        mygoose::text(c, "MyGoose", mygoose::TextOptions { color: c.theme.muted });
        mygoose::text_number(c, s.n, mygoose::TextOptions { size: 56.0, bold: true });
        mygoose::row(c, mygoose::Box { gap: 8.0 }) {
            if mygoose::button(c, "-", mygoose::ButtonOptions { width: 44.0, key: "decrement" }) { s.n -= 1; }
            if mygoose::button(c, "Reset", mygoose::ButtonOptions { disabled: s.n == 0, key: "reset" }) { s.n = 0; }
            if mygoose::button(c, "+", mygoose::ButtonOptions { width: 44.0, primary: true, key: "increment" }) { s.n += 1; }
        };
    };
}
fn main() { var s = Counter {}; mygoose::run(s, mygoose::WindowOptions { title: "MyGoose Counter", width: 360, height: 280 }, view); }
