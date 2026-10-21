namespace test_support;
import mygoose from "../src";

// Compare a previously painted frame with an independent full repaint.
fn full_repaint_equal<Paint>(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    let partial = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); Paint(c);
    assert(partial == mygoose::mg_pixel_hash());
}
fn paint_checked<Paint>(c: mygoose::Context&, cache: mygoose::SceneCache&) -> bool {
    let changed = mygoose::damage(c, cache);
    if changed { Paint(c); full_repaint_equal(c, cache, Paint); }
    changed
}
fn paint_checked(c: mygoose::Context&, cache: mygoose::SceneCache&) -> bool {
    paint_checked(c, cache, mygoose::paint)
}
