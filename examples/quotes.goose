import mygoose from "..";
struct Quotes { clock: mygoose::AnimationClock = mygoose::AnimationClock {}, paused: bool = false }
fn view(s: Quotes&, c: mygoose::Context&) {
    let tick = mygoose::animation_elapsed_ns(s.clock, s.paused) / 16000000;
    mygoose::column(c, mygoose::Box { fill: true, padding: 20.0, gap: 8.0, align: 3 }) {
        mygoose::row(c, mygoose::Box { gap: 20.0, align: 1 }) {
            mygoose::text(c, "Streaming quotes", mygoose::TextOptions { size: 24.0, bold: true });
            mygoose::checkbox(c, "Pause", s.paused, mygoose::CheckOptions { key: "pause" });
        };
        for i in 15 {
            mygoose::row(c, mygoose::Box { height: 27.0, gap: 20.0, background: if i % 2 == 0 { c.theme.surface } else { 0 } }) {
                mygoose::text(c, "STOCK", mygoose::TextOptions { width: 70.0, color: c.theme.muted });
                mygoose::text_number(c, i + 1, mygoose::TextOptions { width: 40.0 });
                mygoose::text_number(c, 10000 + (tick * (i + 3) + i * 701) % 5000);
            };
        }
    };
}
fn main() { var s = Quotes {}; mygoose::run(s, mygoose::WindowOptions { title: "MyGoose Quotes", width: 520, height: 640, animate_ms: 16 }, view); }
