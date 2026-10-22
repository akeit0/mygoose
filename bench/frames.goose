import mygoose from "..";
struct State { count: i64 = 0, offset: mygoose::ScrollState = mygoose::ScrollState {}, mode: i32 = 0 }
fn view(s: State&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 16.0, gap: 8.0, align: 3 });
    mygoose::text(c, "MyGoose benchmark");
    if s.mode == 0 { mygoose::text_number(c, s.count); mygoose::button(c, "Increment"); }
    if s.mode == 1 {
        for i in 50 {
            mygoose::row(c, mygoose::Box { gap: 12.0 });
            mygoose::text_number(c, i); mygoose::text_number(c, s.count + i * 17); mygoose::end(c);
        }
    }
    if s.mode == 2 {
        let range = mygoose::begin_list(c, s.offset, 10000, 24.0, mygoose::Box { height: 400.0, align: 3 }, "list");
        for i in range.first..range.end {
            mygoose::row(c, mygoose::Box { height: 24.0 }); mygoose::text_number(c, i); mygoose::end(c);
        } mygoose::end(c);
    }
    if s.mode == 3 {
        mygoose::text_number(c, s.count);
        mygoose::column(c, mygoose::Box { height: 320.0, gap: 4.0, align: 3 }) {
            for i in 12 {
                mygoose::row(c, mygoose::Box { gap: 24.0 }) {
                    mygoose::text(c, "Unchanged content between updates"); mygoose::text_number(c, i * 17);
                };
            }
        };
        mygoose::text_number(c, s.count);
    }
    mygoose::end(c);
}
fn workload(c: mygoose::Context&, cache: mygoose::SceneCache&, s: State&, mode: i32, raster: bool, bounds_only: bool = false) {
    s.mode = mode; s.count = 0; s.offset.offset = 0.0; c.force = true;
    for i in 20 {
        mygoose::build_frame(c, s, 640.0, 480.0, view); if mygoose::damage(c, cache) && raster { mygoose::paint(c); }
    }
    let paints = c.paints; let start = mygoose::mg_clock_ns(); let iterations = if raster { 1000 } else { 10000 };
    for i in iterations {
        if mode == 1 || mode == 3 { s.count += 1; } if mode == 2 { s.offset.offset = (i % 1000) * 3.0; }
        mygoose::build_frame(c, s, 640.0, 480.0, view);
        if mygoose::damage(c, cache) && raster {
            // Same scene and damage bounds; exercise the ABI fallback without
            // rebuilding the executable or changing the native renderer.
            if bounds_only { mygoose::clear_damage(c.regions); }
            mygoose::paint(c);
        }
    }
    let elapsed = mygoose::mg_clock_ns() - start;
    print("mode=", mode, " raster=", raster, " bounds_only=", bounds_only, " ns/frame=", elapsed / iterations, " paints=", c.paints - paints, " nodes=", c.count,
        " text_bytes=", c.text_count, " working_set_bytes=", mygoose::mg_memory_bytes());
}
fn main() {
    mygoose::headless_open(640, 480); var c = mygoose::Context {}; var cache = mygoose::SceneCache {}; var s = State {};
    print("renderer=", mygoose::mg_renderer(), " (1=Direct2D/DirectWrite, 2=Cairo/Pango, 3=CoreGraphics/CoreText)");
    print("context_array_bytes=", bytes_of(c.nodes).len + bytes_of(c.text_bytes).len + bytes_of(c.previous).len + bytes_of(c.widths).len,
        " scene_cache_array_bytes=", bytes_of(cache.hashes).len + bytes_of(cache.clips).len + bytes_of(cache.bounds).len, " native_storage_bytes=", mygoose::mg_storage_bytes());
    for mode: i32 in 3 { workload(c, cache, s, mode, false); workload(c, cache, s, mode, true); }
    workload(c, cache, s, 3, true, true); workload(c, cache, s, 3, true);
    mygoose::mg_close();
}
