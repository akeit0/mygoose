import .test_support;
import mygoose from "../src";
import std;

struct TableCase {
    table: mygoose::TableState = mygoose::TableState {}, rows: mygoose::ScrollState = mygoose::ScrollState {},
    area: mygoose::ScrollAreaState = mygoose::ScrollAreaState {}, sort: i32 = 7, ascending: bool = true,
    hide: bool = false, reverse: bool = false, light: bool = false, selected: i64 = -1, short: bool = false
}
fn table_case_view(s: TableCase&, c: mygoose::Context&) {
    if s.light { c.theme = mygoose::light_theme(); }
    var columns: mygoose::TableColumn[..3] = [mygoose::TableColumn { id: 7, title: "Name", key: "name", minimum: 80.0, flex: true, align: 0 }];
    let number = mygoose::TableColumn { id: 31, title: "Number", key: "number", width: 90.0, minimum: 50.0 };
    let status = mygoose::TableColumn { id: 2, title: "Status", key: "status", width: 90.0, minimum: 50.0 };
    if s.reverse { if !s.hide { columns.push(status); } columns.push(number); }
    else { columns.push(number); if !s.hide { columns.push(status); } }
    mygoose::column(c, mygoose::Box { fill: true, padding: 12.0, gap: 4.0 }) {
        mygoose::table_header(c, s.table, columns, c.width - 24.0, s.sort, s.ascending);
        mygoose::virtual_list(c, s.rows, 10000, 28.0, mygoose::Box { width: s.table.viewport, height: 220.0 }, "rows") { row =>
            var key: u8[>..] = []; format(key, row);
            let clicked = mygoose::button_content(c, mygoose::Box { width: s.table.viewport, height: 28.0, clip: true },
                mygoose::ButtonOptions { key: key, selected: s.selected == row, style: mygoose::ButtonStyle { flat: true } }) { button =>
                mygoose::table_row(c, s.table) {
                    for col in columns { mygoose::text_number(c, row, mygoose::TextOptions { width: s.table.widths[col.id], align: col.align }); }
                };
            }; if clicked { s.selected = row; }
        };
        mygoose::table_scrollbar(c, s.table, mygoose::TableOptions { scrollbar: mygoose::ScrollbarOptions { key: "horizontal" } });
    };
}
fn area_case_view(s: TableCase&, c: mygoose::Context&) {
    mygoose::scroll_area(c, s.area, mygoose::Box { width: 300.0, height: 180.0 },
        mygoose::ScrollAreaOptions { key: "area", gap: 4.0, scrollbar: mygoose::ScrollbarOptions { key: "vertical" } }) { width =>
        for i: i64 in (if s.short { 2 } else { 40 }) { mygoose::text_number(c, i, mygoose::TextOptions { size: 18.0, width: width }); }
    };
}
fn auto_case_view(s: TableCase&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { width: 300.0, height: 100.0 });
    let clicked = mygoose::button_content(c, mygoose::Box { padding: 5.0 }, mygoose::ButtonOptions { disabled: s.hide, key: "auto" }) { button =>
        mygoose::row(c, mygoose::Box { gap: 4.0 }) { mygoose::text(c, "Alpha"); mygoose::text(c, "Beta"); };
    };
    if clicked { s.selected = 42; }
    mygoose::end(c);
}
fn library_frame<View>(c: mygoose::Context&, cache: mygoose::SceneCache&, s: TableCase&) {
    mygoose::build_frame(c, s, 400.0, 400.0, View);
    assert(c.count < 200);
    test_support::paint_checked(c, cache);
}
fn library_event<View>(c: mygoose::Context&, cache: mygoose::SceneCache&, s: TableCase&, e: mygoose::Event) {
    mygoose::send(c, e); library_frame(c, cache, s, View);
}
fn run_table_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = TableCase {};
    library_frame(c, cache, s, table_case_view);
    let cpu = mygoose::find(c, "sort-number"); let divider = mygoose::find(c, "resize-name");
    let x = divider.x + 4.0; let y = divider.y + 12.0;
    library_event(c, cache, s, mygoose::Event { kind: 2, x: x, y: y }, table_case_view);
    library_event(c, cache, s, mygoose::Event { kind: 3, x: x + 140.0, y: y }, table_case_view);
    assert(mygoose::find(c, "sort-number").x == cpu.x + 140.0 && s.table.widths[31] == 90.0);
    let saved = s.table.preferred[7];
    s.hide = true; library_frame(c, cache, s, table_case_view); assert(s.table.preferred[7] == saved);
    s.hide = false; s.reverse = true; library_frame(c, cache, s, table_case_view);
    assert(mygoose::find(c, "sort-status").x < mygoose::find(c, "sort-number").x && s.table.widths[7] == saved);
    mygoose::click(c, s, "sort-name", table_case_view); assert(!s.ascending);
    let horizontal = mygoose::find(c, "horizontal");
    library_event(c, cache, s, mygoose::Event { kind: 2, x: horizontal.x + horizontal.w - 2.0, y: horizontal.y + 6.0 }, table_case_view);
    library_event(c, cache, s, mygoose::Event { kind: 3, x: horizontal.x + horizontal.w - 2.0, y: horizontal.y + 6.0 }, table_case_view);
    assert(s.table.offset > 0.0);
    library_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_home }, table_case_view); assert(s.table.offset == 0.0);
    s.light = true; library_frame(c, cache, s, table_case_view);
    mygoose::click(c, s, "0", table_case_view); assert(s.selected == 0);
    // Hiding a column during capture cancels its interaction immediately.
    let removed = mygoose::find(c, "resize-status");
    library_event(c, cache, s, mygoose::Event { kind: 2, x: removed.x + 4.0, y: removed.y + 12.0 }, table_case_view);
    s.hide = true; library_frame(c, cache, s, table_case_view); assert(c.pointer.drag_owner == 0 && c.active == 0);
    library_event(c, cache, s, mygoose::Event { kind: 7 }, table_case_view); assert(c.active == 0);
    library_frame(c, cache, s, area_case_view); assert(s.area.content > 180.0);
    library_event(c, cache, s, mygoose::Event { kind: 4, x: 100.0, y: 100.0, delta: -12.5, scroll_pixels: true }, area_case_view);
    assert(s.area.offset == 12.5);
    library_event(c, cache, s, mygoose::Event { kind: 4, x: 100.0, y: 100.0, delta: 12.5, scroll_pixels: true }, area_case_view);
    assert(s.area.offset == 0.0);
    library_event(c, cache, s, mygoose::Event { kind: 4, x: 100.0, y: 100.0, delta: -2.0 }, area_case_view); assert(s.area.offset > 0.0);
    let vertical = mygoose::find(c, "vertical"); let vx = vertical.x + vertical.w * 0.5;
    library_event(c, cache, s, mygoose::Event { kind: 2, x: vx, y: 170.0 }, area_case_view);
    library_event(c, cache, s, mygoose::Event { kind: 3, x: vx, y: 170.0 }, area_case_view);
    assert(s.area.offset > 100.0);
    library_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_home }, area_case_view); assert(s.area.offset == 0.0);
    s.area.offset = 500.0; s.short = true; library_frame(c, cache, s, area_case_view);
    assert(s.area.offset == 0.0 && s.area.content < 180.0 && c.pointer.drag_owner == 0);
    s.hide = false; library_frame(c, cache, s, auto_case_view);
    let auto = mygoose::find(c, "auto");
    assert(abs(auto.h - (c.theme.font_size * 1.4 + 10.0)) < 0.01);
    assert(abs(auto.w - (mygoose::text_width(c, "Alpha", c.theme.font_size) + mygoose::text_width(c, "Beta", c.theme.font_size) + 14.0)) < 0.01);
    mygoose::click(c, s, "auto", auto_case_view); assert(s.selected == 42);
    s.hide = true; s.selected = -1; library_frame(c, cache, s, auto_case_view);
    mygoose::click(c, s, "auto", auto_case_view); assert(s.selected == -1);
    print("PASS: library tables, stable column IDs, resize/suffix movement, hiding/reordering, sorting, virtual rows, compound selection, scroll areas, both scrollbar axes, themes and damage\n");
}
