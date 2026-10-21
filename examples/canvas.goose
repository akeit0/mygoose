import mygoose from "../src";
import mygoose_graphics from "../extras/graphics";

struct CanvasDemo { rounded: bool = true }
fn view(s: CanvasDemo&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 24.0, gap: 16.0 }) {
        mygoose::text(c, "Static vector drawing", mygoose::TextOptions { size: 24.0, bold: true });
        mygoose::checkbox(c, "Rounded corners", s.rounded, mygoose::CheckOptions { key: "rounded" });
        let width = max(160.0, c.width - 48.0);
        mygoose_graphics::canvas(c, width, 200.0, "drawing") { p =>
            mygoose_graphics::rect(p, 0.0, 0.0, width, 200.0,
                mygoose_graphics::Brush { color: c.theme.surface }, if s.rounded { 16.0 } else { 0.0 });
            mygoose_graphics::circle(p, width * 0.35, 100.0, 55.0,
                mygoose_graphics::Brush { color: c.theme.accent });
            mygoose_graphics::line(p, width * 0.55, 55.0, width * 0.8, 145.0,
                mygoose_graphics::Brush { color: c.theme.text, width: 4.0 });
        };
        mygoose::text(c, "No animation runner or motion package is needed.");
    };
}
fn main() {
    var s = CanvasDemo {};
    mygoose_graphics::run(s, mygoose::WindowOptions { title: "MyGoose Canvas", width: 560, height: 360 }, view);
}
