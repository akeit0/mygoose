import mygoose from "..";
struct Events { last: mygoose::Event = mygoose::Event {}, count: i64 = 0 }
fn view(s: Events&, c: mygoose::Context&) {
    if c.event.kind != 0 { s.last = c.event; s.count += 1; }
    mygoose::column(c, mygoose::Box { fill: true, padding: 24.0, gap: 12.0 }) {
        mygoose::text(c, "Input events", mygoose::TextOptions { size: 26.0, bold: true });
        mygoose::text(c, "Move, click, scroll, or type in this window.");
        mygoose::text(c, "Event count"); mygoose::text_number(c, s.count);
        mygoose::text(c, "Kind (move=1, press=2, release=3, wheel=4, key=5, text=6)");
        mygoose::text_number(c, s.last.kind);
        mygoose::text(c, "Key / Unicode scalar"); mygoose::text_number(c, s.last.code);
        if mygoose::button(c, "Reset", mygoose::ButtonOptions { key: "reset" }) { s.count = 0; }
    };
}
fn main() { var s = Events {}; mygoose::run(s, mygoose::WindowOptions { title: "MyGoose Events", width: 560, height: 420 }, view); }
