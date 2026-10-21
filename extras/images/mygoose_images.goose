namespace mygoose_images;
import mygoose from "../../src";
import std;

// Uploaded images are immutable and explicitly owned. Updating one means
// creating a new handle, so scene hashes also detect changed image content.
struct Image { handle: i64 = 0 }
extern fn mg_image_create(rgba: const u8[:], width: i32, height: i32) -> i64;
extern fn mg_image_free(handle: i64);
extern fn mg_image_draw(handle: i64, x: f32, y: f32, width: f32, height: f32, opacity: f32) -> bool;
extern fn mg_image_paint(data: const u8[:], x: f32, y: f32, width: f32, height: f32) -> bool;
fn rgba(bytes: const u8[:], width: i32, height: i32) -> Image { Image { mg_image_create(bytes, width, height) } }
fn destroy(image: Image&) { mg_image_free(image.handle); image.handle = 0; }
fn image(c: mygoose::Context&, value: Image, width: f32, height: f32, key: const u8[:], opacity: f32 = 1.0) {
    assert(value.handle > 0 && width > 0.0 && height > 0.0 && opacity >= 0.0 && opacity <= 1.0);
    var data: u8[..12] = []; let handle: i64[1] = [value.handle]; let alpha: f32[1] = [opacity];
    data.append(bytes_of(handle)); data.append(bytes_of(alpha));
    mygoose::add_leaf(c, mygoose::kind_image, data, width, height, key);
}
fn paint_image(c: mygoose::Context&, index: i32) {
    let n .= c.nodes[index]; if n.kind != mygoose::kind_image || !mygoose::clip_leaf(c, index) { return; }
    // A destroyed or evicted image is harmless. Owners must keep handles live
    // through painting if they want the image to remain visible.
    mg_image_paint(mygoose::node_text(c, index), n.rect.x, n.rect.y, n.rect.w, n.rect.h);
}
fn paint(c: mygoose::Context&) { mygoose::paint(c, paint_image); }
fn run<T, View>(state: T&, options: mygoose::WindowOptions = mygoose::WindowOptions {}) {
    mygoose::run(state, options, View, paint);
}
