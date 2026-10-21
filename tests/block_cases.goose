import mygoose;

struct BlockState {
    scroll: mygoose::ScrollState = mygoose::ScrollState {}, total: i64 = 10000,
    visits: i64 = 0, clicks: i64 = 0, hide: bool = false
}
fn block_item(c: mygoose::Context&, index: i64) {
    mygoose::text(c, "Item"); mygoose::text_number(c, index);
}
fn manual_blocks(s: BlockState&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 12.0, gap: 8.0, align: 3 }, "outer");
    mygoose::row(c);
    if !s.hide { mygoose::text(c, "Heading"); }
    mygoose::end(c);
    mygoose::row(c, mygoose::Box { gap: 8.0 }, "toolbar");
    if mygoose::button(c, "Add", mygoose::ButtonOptions { key: "add" }) { s.clicks += 1; }
    mygoose::text_number(c, s.clicks); mygoose::end(c);
    let range = mygoose::begin_list(c, s.scroll, s.total, 20.0,
        mygoose::Box { height: 80.0, align: 3 }, "items");
    var visited = 0;
    for index in range.first..range.end {
        mygoose::row(c, mygoose::Box { height: 20.0, gap: 12.0 });
        block_item(c, index); visited += 1; mygoose::end(c);
    }
    mygoose::end(c); s.visits = visited;
    mygoose::text(c, "After list"); mygoose::end(c);
    mygoose::text(c, "After column");
}
fn scoped_blocks(s: BlockState&, c: mygoose::Context&) {
    // A named function's ordinary return comes back to row, so row closes.
    fn heading() { if s.hide { return; } mygoose::text(c, "Heading"); }
    mygoose::column(c, mygoose::Box { fill: true, padding: 12.0, gap: 8.0, align: 3 }, "outer") {
        mygoose::row(c, heading);
        mygoose::row(c, mygoose::Box { gap: 8.0 }, "toolbar") {
            if mygoose::button(c, "Add", mygoose::ButtonOptions { key: "add" }) { s.clicks += 1; }
            mygoose::text_number(c, s.clicks);
        };
        var visited = 0;
        mygoose::virtual_list(c, s.scroll, s.total, 20.0,
            mygoose::Box { height: 80.0, align: 3 }, "items") {
            mygoose::row(c, mygoose::Box { height: 20.0, gap: 12.0 }) {
                block_item(c, it); visited += 1;
            };
        };
        s.visits = visited;
        mygoose::text(c, "After list");
    };
    mygoose::text(c, "After column");
}
fn key_lookup_cases(c: mygoose::Context&) {
    mygoose::begin(c, 400.0, 400.0);
    for i in 56 { mygoose::column(c, mygoose::Box { height: 1.0 }) {}; }
    let positional = c.count; assert(positional == 57);
    mygoose::row(c, mygoose::Box { height: 1.0 }) {};
    mygoose::column(c, mygoose::Box {}, "keyed-parent") {
        mygoose::button(c, "Nine", mygoose::ButtonOptions { key: "9" });
    };
    mygoose::finish(c);
    // FNV for the single byte '9' is also mix(parent, 57). The old lookup
    // mistook the earlier unkeyed row for this explicitly keyed button.
    assert(c.nodes[positional].id == mygoose::hash_text("9", c.nodes[0].id));
    let button = mygoose::find_node(c, "9");
    assert(button > positional && c.nodes[button].kind == 3 && c.nodes[button].keyed);
    assert(mygoose::same_rect(mygoose::find(c, "9"), c.nodes[button].rect));
    assert(mygoose::find_node(c, "missing") == -1 && mygoose::find_node(c, "") == -1);
    assert(mygoose::find_node(c, "root") == 0);
    print("PASS: explicit parent-scoped key lookup ignores positional hash collisions and reports missing keys\n");
}
fn run_block_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = BlockState {};
    var ids: u64[1024] = [0; 1024]; var parents: i32[1024] = [0; 1024];
    for mode in 3 {
        s.total = if mode == 2 { 0 } else { 10000 };
        s.scroll.offset = if mode == 1 { 800.0 } else { 0.0 }; s.hide = mode == 2;
        mygoose::build_frame(c, s, 400.0, 400.0, manual_blocks);
        let count = c.count; let visits = s.visits;
        for i: i32 in count { ids[i] = c.nodes[i].id; parents[i] = c.nodes[i].parent; }
        c.force = true; mygoose::damage(c, cache); mygoose::paint(c);
        let pixels = mygoose::mg_pixel_hash();
        mygoose::build_frame(c, s, 400.0, 400.0, scoped_blocks);
        assert(c.parent == -1 && c.count == count && s.visits == visits && visits <= 6);
        for i: i32 in count { assert(ids[i] == c.nodes[i].id && parents[i] == c.nodes[i].parent); }
        assert(!mygoose::damage(c, cache));
        c.force = true; mygoose::damage(c, cache); mygoose::paint(c);
        assert(mygoose::mg_pixel_hash() == pixels);
        mygoose::click(c, s, "add", scoped_blocks); assert(s.clicks == mode + 1);
    }
    // Optional arguments and empty blocks preserve their enclosing parent.
    mygoose::begin(c, 400.0, 400.0);
    mygoose::column(c) { mygoose::row(c) {}; };
    assert(c.parent == 0); mygoose::finish(c);
    key_lookup_cases(c);
    print("PASS: trailing-block layouts, captured state, stable keys/pixels, named callbacks and list virtualization");
}
