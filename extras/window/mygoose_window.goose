namespace mygoose_window;
import mygoose from "../../src";
import mygoose_graphics from "../graphics";
import std;

struct Frame { custom: bool = false, native: bool = false, caption: i32 = -1 }
let control_width: f32 = 46.0;
fn controls_width(frame: Frame&) -> f32 { if frame.custom && !frame.native { control_width * 3.0 } else { 0.0 } }
extern fn mg_window_native_controls() -> bool;
extern fn mg_window_prepare();
extern fn mg_window_frame(enabled: bool, minimum_width: f32, minimum_height: f32) -> bool;
extern fn mg_window_state() -> i32;
extern fn mg_window_command(command: i32) -> bool;
extern fn mg_window_region(kind: i32, x: f32, y: f32, w: f32, h: f32);
fn prepare() { mg_window_prepare(); }
fn attach(frame: Frame&, minimum_width: f32 = 320.0, minimum_height: f32 = 200.0, enabled: bool = true) {
    frame.custom = mg_window_frame(enabled, minimum_width, minimum_height);
    frame.native = mg_window_native_controls();
}
fn detach(frame: Frame&) { mg_window_frame(false, 320.0, 200.0); frame.custom = false; frame.native = false; }
fn caption<Children>(frame: Frame&, c: mygoose::Context&, box: mygoose::Box) {
    mygoose::row(c, box, "window-caption"); frame.caption = c.parent; Children(); mygoose::end(c);
}
fn control(c: mygoose::Context&, kind: i32, key: const u8[:]) -> bool {
    let i = mygoose::button_node(c, "", mygoose::ButtonOptions { width: control_width, key: key,
        style: mygoose::ButtonStyle { flat: true, hover: if kind == 2 { 0xe81123 } else { 0x303033 },
            pressed: if kind == 2 { 0xb50d1b } else { 0x454548 }, radius: 0.0 } });
    c.nodes[i].box.height = 34.0; c.nodes[i].box.padding = 10.0;
    c.parent = i;
    mygoose_graphics::canvas(c, 14.0, 14.0, "window-glyph") { p =>
        let stroke = mygoose_graphics::Brush { color: 0xf2f3f5, width: 1.0 };
        match kind {
            0 => { mygoose_graphics::line(p, 2.0, 7.0, 12.0, 7.0, stroke); },
            1 => {
                if mg_window_state() == 1 {
                    mygoose_graphics::line(p, 4.5, 2.5, 11.5, 2.5, stroke); mygoose_graphics::line(p, 11.5, 2.5, 11.5, 9.5, stroke);
                    mygoose_graphics::rect(p, 2.5, 4.5, 7.0, 7.0, stroke);
                } else { mygoose_graphics::rect(p, 2.5, 2.5, 9.0, 9.0, stroke); }
            },
            2 => { mygoose_graphics::line(p, 3.0, 3.0, 11.0, 11.0, stroke); mygoose_graphics::line(p, 11.0, 3.0, 3.0, 11.0, stroke); },
            _ => {},
        }
    };
    mygoose::end(c); mygoose::activated(c, i)
}
fn controls(frame: Frame&, c: mygoose::Context&) {
    let width = controls_width(frame); if width == 0.0 { return; }
    mygoose::row(c, mygoose::Box { width: width, height: 34.0 }, "window-controls") {
        if control(c, 0, "window-minimize") { mg_window_command(0); }
        if control(c, 1, "window-maximize") { mg_window_command(1); }
        if control(c, 2, "window-close") { mg_window_command(2); }
    };
}
// Register final geometry after build_frame: toolbar controls remain client
// widgets while empty caption space uses the native drag/system-menu behavior.
fn sync(frame: Frame&, c: mygoose::Context&) {
    if !frame.custom { return; }
    mg_window_region(0, 0.0, 0.0, 0.0, 0.0);
    if frame.caption < 0 || frame.caption >= c.count { return; }
    let n .= c.nodes[frame.caption];
    let seed = if n.parent >= 0 { c.nodes[n.parent].id } else { 14695981039346656037 };
    if n.kind != 1 || n.id != mygoose::hash_text("window-caption", seed) { return; }
    let caption = c.nodes[frame.caption].rect;
    let drag = mygoose::Rect { 0.0, caption.y, c.width, caption.h };
    mg_window_region(1, 0.0, drag.y, c.width, drag.h);
    // macOS traffic lights sit above the sidebar's first navigation row.
    if frame.native { mg_window_region(1, 0.0, 0.0, c.width, max(46.0, drag.y + drag.h)); }
    for i: i32 in c.count {
        if mygoose::interactive(c.nodes[i]) || (c.nodes[i].overlay && c.nodes[i].kind == 12) {
            let r = mygoose::intersect(mygoose::intersect(c.nodes[i].rect, c.nodes[i].clip_rect), drag);
            if r.w > 0.0 && r.h > 0.0 { mg_window_region(2, r.x, r.y, r.w, r.h); }
        }
    }
}
