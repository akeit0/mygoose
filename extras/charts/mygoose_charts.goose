namespace mygoose_charts;
import mygoose from "../..";
import std;

struct Palette { surface: u32 = 0x202124, track: u32 = 0x37393e, text: u32 = 0xf2f3f5, muted: u32 = 0x7d8993 }
fn theme_palette(theme: mygoose::Theme) -> Palette {
    Palette { surface: theme.surface, track: theme.border, text: theme.text, muted: theme.muted }
}
struct Options { color: u32 = 0x3794ff, second: u32 = 0xe8b04c, palette: Palette = Palette {}, key: const u8[:] = "" }
extern fn mg_chart(data: const u8[:], x: f32, y: f32, width: f32, height: f32) -> bool;
// One scene leaf, at most 1,480 inline bytes. Samples and colors participate
// in damage hashing; there is no registry, per-dot node or retained texture.
fn chart(c: mygoose::Context&, kind: i32, width: f32, height: f32, ratio: f32,
    values: const f32[:], columns: i32, span: i32, options: Options) {
    assert(width > 0.0 && height > 0.0);
    var bytes: u8[..1480] = [];
    let header: i32[4] = [kind, options.color as i32, options.second as i32, columns];
    let colors: u32[4] = [options.palette.surface, options.palette.track, options.palette.text, options.palette.muted];
    let scale: f32[1] = [ratio]; let interval: i32[1] = [span];
    bytes.append(bytes_of(header)); bytes.append(bytes_of(colors)); bytes.append(bytes_of(scale)); bytes.append(bytes_of(interval)); bytes.append(bytes_of(values));
    mygoose::add_leaf(c, mygoose::kind_chart, bytes, width, height, options.key);
}
fn history_chart(c: mygoose::Context&, kind: i32, width: f32, height: f32, values: const f32[:], scale: f32, span: i32, options: Options) {
    assert(width >= 32.0 && height >= 24.0 && width <= 16384.0 && height <= 16384.0);
    assert(values.len >= 2 && values.len <= 360 && values.len % 2 == 0 && scale > 0.0 && span >= 1 && span <= 3600);
    chart(c, kind, width, height, scale, values, (values.len / 2) as i32, span, options);
}
// Interleaved primary/secondary samples. A negative value is unavailable;
// use -1 for every secondary sample when plotting just one series.
fn dots(c: mygoose::Context&, width: f32, height: f32, values: const f32[:], scale: f32, span: i32, options: Options = Options {}) {
    history_chart(c, 0, width, height, values, scale, span, options);
}
// A discrete history: exactly one vertical bar per sample pair, oldest to
// newest. The caller advances the history only when a new sample arrives.
fn bars(c: mygoose::Context&, width: f32, height: f32, values: const f32[:], scale: f32, span: i32, options: Options = Options {}) {
    history_chart(c, 3, width, height, values, scale, span, options);
}
// Hit testing uses the same plot padding and discrete slots as the native
// bar renderer. Call after layout; clip excludes scrolled-off chart regions.
struct HistoryHit { index: i32 = -1, x: f32 = 0.0, plot: mygoose::Rect = mygoose::Rect {} }
fn bar_hover(rect: mygoose::Rect, clip: mygoose::Rect, x: f32, y: f32, columns: i32) -> HistoryHit {
    assert(columns >= 1 && columns <= 180);
    if rect.w < 32.0 || rect.h < 24.0 { return HistoryHit {}; }
    let plot = mygoose::Rect { rect.x + 12.0, rect.y + 8.0, rect.w - 24.0, rect.h - (if rect.h >= 100.0 { 36.0 } else { 16.0 }) };
    if !mygoose::contains(mygoose::intersect(plot,clip),x,y) { return HistoryHit {}; }
    let index = min(columns - 1, ((x - plot.x) * columns / plot.w) as! i32);
    HistoryHit { index: index, x: plot.x + (index + 0.5) * plot.w / columns, plot: plot }
}
fn ring(c: mygoose::Context&, width: f32, height: f32, ratio: f32, options: Options = Options {}) {
    assert(width >= 24.0 && height >= 24.0 && width <= 16384.0 && height <= 16384.0 && ratio >= 0.0 && ratio <= 1.0e15);
    let empty: f32[0] = []; chart(c, 1, width, height, ratio, empty, 0, 0, options);
}
fn bar(c: mygoose::Context&, width: f32, height: f32, ratio: f32, options: Options = Options {}) {
    assert(width >= 1.0 && height >= 1.0 && width <= 16384.0 && height <= 16384.0 && ratio >= 0.0 && ratio <= 1.0e15);
    let empty: f32[0] = []; chart(c, 2, width, height, ratio, empty, 0, 0, options);
}
fn paint_chart(c: mygoose::Context&, index: i32) {
    let n .= c.nodes[index]; if n.kind != mygoose::kind_chart || !mygoose::clip_leaf(c, index) { return; }
    assert(mg_chart(mygoose::node_text(c, index), n.rect.x, n.rect.y, n.rect.w, n.rect.h));
}
fn paint(c: mygoose::Context&) { mygoose::paint(c, paint_chart); }
fn run<T, View>(state: T&, options: mygoose::WindowOptions = mygoose::WindowOptions {}) { mygoose::run(state, options, View, paint); }
