namespace mygoose;
import mygoose from "../../src";
import mygoose_charts from "../../extras/charts";

// Monitor colors adapt the reusable optional package to this application's theme.
fn monitor_chart(c: Context&, kind: i32, width: f32, height: f32, color: u32,
    ratio: f32, values: const f32[:], columns: i32 = 0, span: i32 = 0, second: u32 = 0xe8b04c) {
    let key = match kind { 0 => "history", 1 => "utilization", _ => "bar" };
    let options = mygoose_charts::Options { color: color, second: second, key: key };
    match kind {
        0 => { assert(values.len == columns * 2); mygoose_charts::dots(c, width, height, values, ratio, span, options); },
        1 => { mygoose_charts::ring(c, width, height, ratio, options); },
        _ => { mygoose_charts::bar(c, width, height, ratio, options); },
    }
}
fn monitor_ring(c: Context&, width: f32, height: f32, ratio: f32, color: u32) {
    let empty: f32[0] = []; monitor_chart(c, 1, width, height, color, ratio, empty);
}
fn monitor_bar(c: Context&, width: f32, ratio: f32, color: u32, height: f32 = 9.0) {
    let empty: f32[0] = []; monitor_chart(c, 2, width, height, color, ratio, empty);
}
