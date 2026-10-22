import .test_support;
import mygoose from "..";
import mygoose_charts from "../extras/charts";
import std;
struct Charts { ratio: f32 = 0.0, offset: f32 = 0.0, light: bool = false, value: f32 = 40.0, bars: bool = false }
fn view(s: Charts&, c: mygoose::Context&) {
    let palette = mygoose_charts::Palette { surface: if s.light { 0xffffff } else { 0x202124 },
        track: if s.light { 0xdde0e5 } else { 0x37393e }, text: if s.light { 0x111111 } else { 0xf2f3f5 }, muted: 0x777777 };
    let options = mygoose_charts::Options { color: 0x3794ff, palette: palette };
    mygoose::column(c, mygoose::Box { width: 340.0, height: 300.0, padding: 10.0, gap: 8.0, clip: true, background: palette.surface }) {
        mygoose::column(c, mygoose::Box { height: s.offset }) {};
        let values: f32[6] = [-1.0,-1.0, 0.0,-1.0, s.value,10.0];
        if s.bars { mygoose_charts::bars(c, 320.0, 126.0, values, 100.0, 60, options); }
        else { mygoose_charts::dots(c, 320.0, 126.0, values, 100.0, 60, options); }
        mygoose::row(c, mygoose::Box { gap: 16.0, align: 1 }) {
            mygoose_charts::ring(c, 120.0, 120.0, s.ratio, options);
            mygoose_charts::bar(c, 180.0, 10.0, s.ratio, options);
        };
    };
}
fn frame(s: Charts&, c: mygoose::Context&, cache: mygoose::SceneCache&) {
    mygoose::build_frame(c, s, 360.0, 320.0, view); assert(c.count < 16 && c.text_count < 512);
    var ids: u64[..3] = [];
    for i: i32 in c.count { if c.nodes[i].kind == mygoose::kind_chart { for id in ids { assert(c.nodes[i].id != id); } ids.push(c.nodes[i].id); } }
    assert(ids.len == 3);
    assert(mygoose::damage(c, cache)); mygoose_charts::paint(c);
    test_support::full_repaint_equal(c, cache, mygoose_charts::paint);
}
fn hover_cases() {
    let rect = mygoose::Rect { 10.0,20.0,264.0,112.0 }; let clip = mygoose::Rect { w: 360.0, h: 320.0 };
    assert(mygoose_charts::bar_hover(rect,clip,22.0,28.0,120).index == 0);
    assert(mygoose_charts::bar_hover(rect,clip,23.99,28.0,120).index == 0);
    let second = mygoose_charts::bar_hover(rect,clip,24.0,28.0,120);
    assert(second.index == 1 && second.x == 25.0 && second.plot.h == 76.0);
    assert(mygoose_charts::bar_hover(rect,clip,261.99,103.99,120).index == 119);
    assert(mygoose_charts::bar_hover(rect,clip,262.0,50.0,120).index == -1);
    assert(mygoose_charts::bar_hover(rect,clip,50.0,104.0,120).index == -1); // Axis labels.
    assert(mygoose_charts::bar_hover(rect,clip,21.99,50.0,120).index == -1);
    let cropped = mygoose::Rect { 100.0,40.0,100.0,40.0 };
    assert(mygoose_charts::bar_hover(rect,cropped,99.0,50.0,120).index == -1);
    assert(mygoose_charts::bar_hover(rect,cropped,100.0,40.0,120).index == 39);
    assert(mygoose_charts::bar_hover(rect,cropped,100.0,80.0,120).index == -1);
    assert(mygoose_charts::bar_hover(rect,clip,150.0,50.0,1).index == 0);
    let small = mygoose::Rect { w: 32.0, h: 24.0 };
    assert(mygoose_charts::bar_hover(small,clip,12.01,8.0,180).index == 0);
    assert(mygoose_charts::bar_hover(small,clip,19.99,15.99,180).index == 179);
    assert(mygoose_charts::bar_hover(small,clip,16.0,16.0,180).index == -1);
    print("PASS: discrete bar hover slots, plot/axis boundaries, clipped scrolling, narrow and single-sample histories\n");
}
fn main() {
    hover_cases();
    mygoose::headless_open(360,320); var state = Charts {}; var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    frame(state,c,cache); state.ratio = 0.56; frame(state,c,cache); state.ratio = 1.25; frame(state,c,cache);
    state.light = true; frame(state,c,cache); state.offset = 17.5; frame(state,c,cache);
    state.value = 0.0; frame(state,c,cache); state.value = -1.0; frame(state,c,cache);
    state.bars = true; frame(state,c,cache); state.value = 50.0; frame(state,c,cache);
    mygoose::mg_close(); print("PASS: reusable chart API, palettes, changing samples/ratios, clipping and partial/full pixels\n");
}
