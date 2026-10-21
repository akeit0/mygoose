namespace mygoose_graphics;
import mygoose from "../../src";
import std;
import math;

struct Brush { color: u32 = 0xffffff, opacity: f32 = 1.0, width: f32 = 0.0 }
struct Segment { verb: u8 = 0, x: f32 = 0.0, y: f32 = 0.0, x2: f32 = 0.0, y2: f32 = 0.0, x3: f32 = 0.0, y3: f32 = 0.0 }
struct Path { segments: Segment[..128] = [], x: f32 = 0.0, y: f32 = 0.0, start_x: f32 = 0.0, start_y: f32 = 0.0, open: bool = false }
struct Transform { a: f32 = 1.0, b: f32 = 0.0, c: f32 = 0.0, d: f32 = 1.0, x: f32 = 0.0, y: f32 = 0.0, scale: f32 = 1.0 }
struct Painter { commands: u8[..8192] = [], transform: Transform = Transform {}, opacity: f32 = 1.0 }
extern fn mg_vector(commands: const u8[:], x: f32, y: f32) -> bool;

fn finite(value: f32) -> bool { !is_nan(value) && !is_inf(value) }
fn move_to(p: Path&, x: f32, y: f32) {
    p.segments.push(Segment { verb: 0, x: x, y: y }); p.x = x; p.y = y; p.start_x = x; p.start_y = y; p.open = true;
}
fn line_to(p: Path&, x: f32, y: f32) { assert(p.open); p.segments.push(Segment { verb: 1, x: x, y: y }); p.x = x; p.y = y; }
fn cubic_to(p: Path&, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
    assert(p.open); p.segments.push(Segment { verb: 2, x: x1, y: y1, x2: x2, y2: y2, x3: x, y3: y }); p.x = x; p.y = y;
}
fn quad_to(p: Path&, cx: f32, cy: f32, x: f32, y: f32) {
    cubic_to(p, p.x + (cx - p.x) * (2.0 / 3.0), p.y + (cy - p.y) * (2.0 / 3.0), x + (cx - x) * (2.0 / 3.0), y + (cy - y) * (2.0 / 3.0), x, y);
}
fn close(p: Path&) { assert(p.open); p.segments.push(Segment { verb: 3 }); p.x = p.start_x; p.y = p.start_y; p.open = false; }
fn reset(p: Path&) { p.segments.clear(); p.open = false; }
fn point(p: Painter&, x: f32, y: f32) {
    let t = p.transform; let px = t.a * x + t.c * y + t.x; let py = t.b * x + t.d * y + t.y;
    assert(finite(px) && finite(py) && abs(px) <= 1000000.0 && abs(py) <= 1000000.0);
    let coordinates: f32[2] = [px, py]; p.commands.append(bytes_of(coordinates));
}
fn draw_path(p: Painter&, path: Path&, brush: Brush = Brush {}) {
    if path.segments.len == 0 { return; }
    let alpha = brush.opacity * p.opacity; let width = brush.width * p.transform.scale;
    assert(finite(alpha) && alpha >= 0.0 && alpha <= 1.0);
    assert(finite(width) && width >= 0.0 && width <= 4096.0);
    let color: u32[1] = [brush.color]; let style: f32[2] = [alpha, width]; let count: i32[1] = [path.segments.len as i32];
    p.commands.append(bytes_of(color)); p.commands.append(bytes_of(style)); p.commands.append(bytes_of(count));
    for segment in path.segments {
        p.commands.push(segment.verb);
        if segment.verb <= 2 { point(p, segment.x, segment.y); }
        if segment.verb == 2 { point(p, segment.x2, segment.y2); point(p, segment.x3, segment.y3); }
    }
}
fn ellipse(p: Painter&, x: f32, y: f32, rx: f32, ry: f32, brush: Brush = Brush {}) {
    assert(rx >= 0.0 && ry >= 0.0); if rx == 0.0 || ry == 0.0 { return; }
    var path = Path {}; let k: f32 = 0.55228475;
    move_to(path, x + rx, y);
    cubic_to(path, x + rx, y + ry * k, x + rx * k, y + ry, x, y + ry);
    cubic_to(path, x - rx * k, y + ry, x - rx, y + ry * k, x - rx, y);
    cubic_to(path, x - rx, y - ry * k, x - rx * k, y - ry, x, y - ry);
    cubic_to(path, x + rx * k, y - ry, x + rx, y - ry * k, x + rx, y); close(path); draw_path(p, path, brush);
}
fn circle(p: Painter&, x: f32, y: f32, radius: f32, brush: Brush = Brush {}) { ellipse(p, x, y, radius, radius, brush); }
fn rect(p: Painter&, x: f32, y: f32, w: f32, h: f32, brush: Brush = Brush {}, radius: f32 = 0.0) {
    assert(w >= 0.0 && h >= 0.0 && radius >= 0.0); if w == 0.0 || h == 0.0 { return; }
    let r = min(radius, min(w, h) * 0.5); let k = r * 0.55228475; var path = Path {};
    move_to(path, x + r, y); line_to(path, x + w - r, y);
    cubic_to(path, x + w - r + k, y, x + w, y + r - k, x + w, y + r);
    line_to(path, x + w, y + h - r); cubic_to(path, x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h);
    line_to(path, x + r, y + h); cubic_to(path, x + r - k, y + h, x, y + h - r + k, x, y + h - r);
    line_to(path, x, y + r); cubic_to(path, x, y + r - k, x + r - k, y, x + r, y); close(path); draw_path(p, path, brush);
}
fn line(p: Painter&, x: f32, y: f32, x2: f32, y2: f32, brush: Brush = Brush { width: 1.0 }) {
    var path = Path {}; move_to(path, x, y); line_to(path, x2, y2);
    var stroke = brush; if stroke.width == 0.0 { stroke.width = 1.0; } draw_path(p, path, stroke);
}
fn translate<Children>(p: Painter&, x: f32, y: f32) {
    let old = p.transform; p.transform.x += old.a * x + old.c * y; p.transform.y += old.b * x + old.d * y;
    Children(); p.transform = old;
}
fn rotate<Children>(p: Painter&, radians: f32) {
    let old = p.transform; let c = cos(radians); let s = sin(radians);
    p.transform.a = old.a * c + old.c * s; p.transform.b = old.b * c + old.d * s;
    p.transform.c = old.c * c - old.a * s; p.transform.d = old.d * c - old.b * s;
    Children(); p.transform = old;
}
fn scale<Children>(p: Painter&, factor: f32) {
    assert(finite(factor) && factor > 0.0); let old = p.transform;
    p.transform.a *= factor; p.transform.b *= factor; p.transform.c *= factor; p.transform.d *= factor; p.transform.scale *= factor;
    Children(); p.transform = old;
}
fn opacity<Children>(p: Painter&, alpha: f32) {
    assert(finite(alpha) && alpha >= 0.0 && alpha <= 1.0); let old = p.opacity;
    p.opacity *= alpha; Children(); p.opacity = old;
}
fn canvas<Draw: fn(Painter&)>(c: mygoose::Context&, width: f32, height: f32, key: const u8[:]) {
    assert(width > 0.0 && height > 0.0 && key.len > 0);
    var painter = Painter {}; let target: Painter& = painter; Draw(target);
    mygoose::add_leaf(c, mygoose::kind_canvas, painter.commands, width, height, key);
}
fn paint_canvas(c: mygoose::Context&, i: i32) {
    let n .= c.nodes[i]; if n.kind != mygoose::kind_canvas || !mygoose::clip_leaf(c, i) { return; }
    assert(mg_vector(mygoose::node_text(c, i), n.rect.x, n.rect.y));
}
fn paint(c: mygoose::Context&) { mygoose::paint(c, paint_canvas); }

// Static drawing has the same two-argument View contract as core apps.
// Animated drawing composes motion_app::run with this package's painter.
fn run<T, View>(state: T&, options: mygoose::WindowOptions = mygoose::WindowOptions {}) {
    mygoose::run(state, options, View, paint);
}
