# Optional bitmap images

`mygoose_images` uploads immutable **RGBA8 pixels** and draws them with scaling,
clipping and opacity. It uses Direct2D on Windows, Cairo on
Linux and CoreGraphics on macOS. All three native adapters are tested. No
decoder, bundled image assets or font dependency is added.
PNG/JPEG file decoding is not implemented by this package yet.

```goose
import mygoose_images from "path/to/mygoose/extras/images";

let pixels: u8[16] = [255,0,0,255, 0,255,0,255,
                     0,0,255,128, 255,255,255,0];
var picture = mygoose_images::rgba(pixels, 2, 2);
assert(picture.handle > 0); // zero means invalid input or capacity/allocation failure

// Inside a view, after importing mygoose at the application's root:
mygoose_images::image(c, picture, 64.0, 64.0, "picture", 0.8);

// Use mygoose_images::run(state, options, view) for a normal image-only app.
// For a custom loop, use mygoose_images::paint, or compose with charts
// after declaring mygoose_charts at the root:
fn paint_extra(c: mygoose::Context&, i: i32) {
    mygoose_charts::paint_chart(c, i);
    mygoose_images::paint_image(c, i);
}
// mygoose::paint(c, paint_extra);
// A combined app can pass its painter directly:
// mygoose::run(state, options, view, combined_paint);

// Keep the image alive through painting; release it when no longer shown:
mygoose_images::destroy(picture);
```

Input rows are tightly packed, top to bottom, with straight alpha. Uploads copy
and premultiply the pixels; callers may reuse their source buffers immediately.
Handle IDs are never reused. Destroying a handle twice is harmless and stale
handles draw nothing. Images are owned explicitly, on the UI thread; destroy
them after their last paint, before starting a different window lifecycle.
A replacement image gets a new handle, which
invalidates the scene cache automatically.

Storage is allocated on demand, capped at 128 images, 4096×4096 per image and
64 MiB of uploaded pixel data in total. Native renderer copies can require
additional memory. No buffers or fields are added to the UI context or nodes.
The native image object is linked only when
image calls are reachable. Importing without using images has no runtime cost.

The activity monitor uses this path for Windows executable icons and macOS
application/helper icons. Bounded caches share uploaded images and avoid
repeated PID/creation-time lookups. Windows extraction runs on a worker; RGBA
uploads and renderer resources stay on the UI thread. Linux and inaccessible
processes use a vector fallback.

```powershell
python tools/build.py images-test --mode small
python tools/wsl.py images-test --mode small
```

Tests verify actual alpha/opacity pixels, clipping, scaling, invalid dimensions,
stale handles and capacity, plus image-node partial/full repaint equivalence.
