# Optional charts

Dot/vertical-bar histories, percentage rings and horizontal bars, using the existing native
drawing ABI on Windows, Linux and macOS. No monitor, sampler, vector or motion
package is required. Charts add nothing to core `Context` or `Node` storage.

```goose
import mygoose from "path/to/mygoose";
import mygoose_charts from "path/to/mygoose/extras/charts";

struct ChartDemo { fraction: f32 = 0.56 }
fn view(s: ChartDemo&, c: mygoose::Context&) {
    let palette = mygoose_charts::theme_palette(c.theme);
    // Interleaved primary/secondary values. -1 is unavailable; 0 is measured idle.
    let samples: f32[8] = [-1.0,-1.0, 0.0,-1.0, 35.0,10.0, 60.0,15.0];
    mygoose::column(c, mygoose::Box { padding: 16.0, gap: 12.0 }) {
        mygoose_charts::dots(c, 300.0, 112.0, samples, 100.0, 60,
            mygoose_charts::Options { palette: palette, key: "dots" });
        mygoose_charts::bars(c, 300.0, 112.0, samples, 100.0, 60,
            mygoose_charts::Options { palette: palette, key: "bars" });
        mygoose_charts::ring(c, 112.0, 112.0, s.fraction,
            mygoose_charts::Options { palette: palette, key: "ring" });
        mygoose_charts::bar(c, 260.0, 9.0, s.fraction,
            mygoose_charts::Options { palette: palette, key: "progress" });
    };
}
fn main() {
    var s = ChartDemo {};
    mygoose_charts::run(s, mygoose::WindowOptions { width: 340, height: 440 }, view);
}
```

Use `mygoose_charts::run`/`paint` for apps containing basic controls and charts.
For a custom painter, call `paint_chart(c, index)` from the extra-node callback
passed to `mygoose::paint`. Omitted keys use the core's positional identity;
assign distinct stable `Options.key` values when charts can move or reorder.
The monitor combines this painter with optional vectors and images.
The complete [`charts` example](../../examples/charts.goose) has an interactive
slider and uses only the core and chart packages.

`dots` takes 1–180 pairs of values, a positive shared scale, and a range of
1–3,600 seconds. It stacks the primary above the secondary and draws missing
channels dim. The caller owns sampling, history and aggregation. Charts never
generate history or schedule a timer. Time labels appear at heights of at least
100 pixels. Resizing changes dot density while retaining the first and newest
input buckets. Rings and horizontal `bar` indicators take a nonnegative fraction; fractions above one
saturate the shape while a ring still prints the actual percentage.

`bars` takes the same sample pairs, scale and time span as `dots`, drawing one
vertical bar per pair, oldest on the left and newest on the right. Both channels
stack, with exact heights rather than dot-row quantization. Width changes resize
the bars without resampling the history. Append one sample and discard the
oldest on each sampling tick to shift every old bar one slot left; there is no
interpolation between ticks. Missing/zero samples draw no active height. Keep
the scale stable to avoid resizing old bars as each new measurement arrives.
The singular `bar` remains a horizontal fraction/progress indicator.

`bar_hover(rect, clip, mouse_x, mouse_y, columns)` returns a `HistoryHit` with the
input sample index, snapped slot center `x`, and plot bounds. Index `-1` means
outside the visible plot (including axes and padding). Call after layout so the
current geometry and scroll clip are used. It matches discrete bar slots even
when narrow; it does not resample or infer time from the chart's span. The caller
owns timestamps, values and tooltip formatting. The Performance sample keeps
actual start/end timestamps for each bucket and adds passive scene annotations
before damage, so tooltip movement/removal uses normal partial repainting.

`Options.palette` supplies `surface`, `track`, `text` and `muted` RGB colors.
`theme_palette(context.theme)` copies those colors from the current UI theme.
Match `surface` to the containing card for the ring's center. All coordinates
are logical pixels and chart bounds clip painting. Dots need at least 32×24
pixels and rings 24×24; dimensions are capped at 16,384 pixels.

Each chart uses one kind-16 scene leaf and at most 1,480 bytes in the existing
frame arena. Colors and samples participate in damage hashing. There are no
per-dot nodes, retained textures, persistent chart buffers or new OS libraries.
On macOS rings use a round-capped CoreGraphics arc, with a closed ellipse for
a full ring. Other backends retain the portable overlapping-disk renderer.
The macOS core also fills circular rounded rectangles directly, benefiting
dots and any other caller of that primitive without a chart-specific core path.
The native payload is validated
before drawing, including finite values, palette colors and exact byte lengths.

```powershell
python tools/build.py charts --mode small --run
python tools/build.py charts-test --mode debug
python tools/wsl.py charts-test --mode small
```
