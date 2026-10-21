import mygoose from "../src";
import mygoose_charts from "../extras/charts";
import std;
struct Charts { fraction: f32 = 0.56 }
fn view(s: Charts&, c: mygoose::Context&) {
    let palette = mygoose_charts::theme_palette(c.theme);
    let options = mygoose_charts::Options { color: 0x32d583, palette: palette };
    mygoose::column(c, mygoose::Box { fill: true, padding: 24.0, gap: 18.0 }) {
        mygoose::text(c, "Reusable charts", mygoose::TextOptions { size: 24.0, bold: true });
        mygoose::text(c, "Example data · dots, rings and bars · no monitor dependencies", mygoose::TextOptions { color: c.theme.muted });
        mygoose::column(c, mygoose::Box { padding: 18.0, gap: 16.0, background: c.theme.surface, radius: 16.0 }) {
            var values: f32[..120] = [];
            for i: i32 in 60 { values.push(if i < 12 { -1.0 } else { 20.0 + (i % 17) * 2.0 }); values.push(if i < 12 { -1.0 } else { 8.0 }); }
            mygoose_charts::dots(c, 548.0, 132.0, values, 100.0, 60, options);
            mygoose::row(c, mygoose::Box { gap: 24.0, align: 1 }) {
                mygoose_charts::ring(c, 112.0, 112.0, s.fraction, options);
                mygoose::column(c, mygoose::Box { gap: 16.0 }) {
                    mygoose::slider(c, s.fraction, 0.0, 1.0, mygoose::SliderOptions { width: 260.0, step: 0.01, key: "fraction" });
                    mygoose_charts::bar(c, 260.0, 9.0, s.fraction, options);
                };
            };
        };
    };
}
fn main() { var state = Charts {}; mygoose_charts::run(state, mygoose::WindowOptions { title: "MyGoose Charts", width: 640, height: 460 }, view); }
