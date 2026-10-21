import mygoose from "../src";
import mygoose_images from "../extras/images";

struct ImageDemo { picture: mygoose_images::Image = mygoose_images::Image {}, opacity: f32 = 1.0 }
fn view(s: ImageDemo&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, gap: 18.0, padding: 24.0 }) {
        mygoose::text(c, "Bitmap images", mygoose::TextOptions { size: 26.0, bold: true });
        mygoose::text(c, "RGBA pixels, scaling, transparency and clipping.");
        mygoose::slider(c, s.opacity, 0.0, 1.0, mygoose::SliderOptions { width: 280.0, step: 0.05, key: "opacity" });
        mygoose::row(c, mygoose::Box { gap: 24.0, align: 1 }) {
            mygoose_images::image(c, s.picture, 96.0, 96.0, "small", s.opacity);
            mygoose_images::image(c, s.picture, 192.0, 192.0, "large", s.opacity);
        };
    };
}
fn main() {
    var pixels: u8[4096] = [0; 4096];
    for y in 32 { for x in 32 {
        let i = (y * 32 + x) * 4; pixels[i] = (x * 255 / 31) as u8;
        pixels[i+1] = (y * 255 / 31) as u8; pixels[i+2] = 220;
        pixels[i+3] = if (x / 8 + y / 8) % 2 == 0 { 255 } else { 80 };
    } }
    var s = ImageDemo { picture: mygoose_images::rgba(pixels, 32, 32) }; assert(s.picture.handle > 0);
    mygoose_images::run(s, mygoose::WindowOptions { title: "MyGoose Images", width: 440, height: 380 }, view);
    mygoose_images::destroy(s.picture);
}
