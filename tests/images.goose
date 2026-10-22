import .test_support;
import mygoose from "..";
import mygoose_images from "../extras/images";
import std;

struct Images {
    bitmap: mygoose_images::Image = mygoose_images::Image {},
    offset: f32 = 0.0, opacity: f32 = 1.0, visible: bool = true
}
fn view(s: Images&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { width: 80.0, height: 60.0, padding: 7.0, clip: true, background: 0x202020 }) {
        mygoose::column(c, mygoose::Box { height: s.offset }) {};
        if s.visible { mygoose_images::image(c, s.bitmap, 60.0, 45.0, "picture", s.opacity); }
    };
}
fn frame(s: Images&, c: mygoose::Context&, cache: mygoose::SceneCache&) {
    mygoose::build_frame(c, s, 100.0, 100.0, view);
    if s.visible {
        let r = mygoose::find(c, "picture");
        assert(mygoose::hit(c, r.x + 1.0, r.y + 1.0) == 0);
        mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_tab });
        assert(c.focus == 0);
    }
    if mygoose::damage(c, cache) { mygoose_images::paint(c); }
    test_support::full_repaint_equal(c, cache, mygoose_images::paint);
}
fn main() {
    mygoose::headless_open(100, 100);
    let rgba: u8[16] = [255,0,0,255, 0,255,0,255, 0,0,255,128, 255,255,255,0];
    var s = Images { bitmap: mygoose_images::rgba(rgba, 2, 2) }; assert(s.bitmap.handle > 0);
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    frame(s, c, cache); s.opacity = 0.4; frame(s, c, cache); s.offset = 13.25; frame(s, c, cache);
    s.visible = false; frame(s, c, cache); s.visible = true; frame(s, c, cache);
    let old = s.bitmap.handle; mygoose_images::destroy(s.bitmap); assert(s.bitmap.handle == 0);
    s.bitmap = mygoose_images::rgba(rgba, 2, 2); assert(s.bitmap.handle > old); frame(s, c, cache);
    mygoose_images::destroy(s.bitmap); mygoose::mg_close();
    print("PASS: optional RGBA image nodes, resizing, opacity, clipping, removal, replacement and partial/full pixels\n");
}
