import .test_support;
import mygoose from "..";
import std;
import .frame;
import .damage_cases;
import .text_edit_cases;
import .block_cases;
import .button_cases;
import .table_cases;
import .interaction_cases;
import .selection_cases;
import .scroll_cases;

struct State {
    count: i64 = 0, checked: bool = false, enabled: bool = true, volume: f32 = 25.0,
    input: mygoose::TextInput = mygoose::TextInput {},
    scroll: mygoose::ScrollState = mygoose::ScrollState {}, rows: i64 = 10000,
    range: mygoose::ListRange = mygoose::ListRange {}, show: bool = true,
    doc: mygoose::TextDocument = mygoose::TextDocument {}
}
fn view(s: State&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 10.0, gap: 8.0, align: 3 });
    mygoose::row(c, mygoose::Box { gap: 8.0 });
    if mygoose::button(c, "Increment", mygoose::ButtonOptions { key: "inc", disabled: !s.enabled }) { s.count += 1; }
    if s.show { if mygoose::button(c, "Remove", mygoose::ButtonOptions { key: "remove" }) { s.show = false; } }
    mygoose::end(c);
    mygoose::text_number(c, s.count);
    mygoose::checkbox(c, "Enabled", s.checked, mygoose::CheckOptions { key: "check" });
    mygoose::slider(c, s.volume, 0.0, 100.0, mygoose::SliderOptions { key: "slider" });
    mygoose::text_input(c, s.input, mygoose::InputOptions { key: "input", placeholder: "Type here" });
    s.range = mygoose::begin_list(c, s.scroll, s.rows, 20.0, mygoose::Box { height: 100.0, align: 3, background: c.theme.surface }, "list");
    for row in s.range.first..s.range.end {
        mygoose::row(c, mygoose::Box { height: 20.0 }); mygoose::text_number(c, row); mygoose::end(c);
    }
    mygoose::end(c); mygoose::end(c);
}
fn frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: State&) -> bool {
    mygoose::build_frame(c, s, 400.0, 400.0, view);
    test_support::paint_checked(c, cache)
}
fn event(c: mygoose::Context&, cache: mygoose::SceneCache&, s: State&, e: mygoose::Event) {
    mygoose::send(c, e); frame(c, cache, s);
}
fn click(c: mygoose::Context&, cache: mygoose::SceneCache&, s: State&, key: const u8[:]) {
    mygoose::click(c, s, key, view); if mygoose::damage(c, cache) { mygoose::paint(c); }
}
fn area_view(s: State&, c: mygoose::Context&) {
    mygoose::text_area(c, s.doc, mygoose::AreaOptions { width: 380.0, height: 100.0, key: "doc" });
}
fn area_event(c: mygoose::Context&, cache: mygoose::SceneCache&, s: State&, e: mygoose::Event) {
    mygoose::send(c, e); mygoose::build_frame(c, s, 400.0, 400.0, area_view);
    test_support::paint_checked(c, cache);
}
let choices: const u8[:][20] = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa",
    "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho", "Sigma", "Tau", "Omega"];
struct SelectState {
    selected: i64 = 0, disabled: bool = false, empty: bool = false, show: bool = true,
    bottom: bool = false, presses: i64 = 0, card_offset: f32 = 0.0,
    shadow: bool = true, card: bool = true
}
fn select_view(s: SelectState&, c: mygoose::Context&) {
    c.theme = mygoose::light_theme();
    mygoose::column(c, mygoose::Box { fill: true, padding: 16.0, gap: 12.0, align: 3 });
    if s.bottom { mygoose::column(c, mygoose::Box { height: 280.0 }); mygoose::end(c); }
    // A popup must escape this short parent's clipping rectangle.
    mygoose::column(c, mygoose::Box { height: 40.0, clip: true });
    if s.show { mygoose::select(c, if s.empty { choices[..0] } else { choices[..] }, s.selected,
        mygoose::SelectOptions { visible_rows: 5, disabled: s.disabled, key: "select" }); }
    mygoose::end(c);
    if mygoose::button(c, "Under popup", mygoose::ButtonOptions { width: 360.0, key: "under" }) { s.presses += 1; }
    mygoose::row(c);
    mygoose::column(c, mygoose::Box { width: s.card_offset }); mygoose::end(c);
    if s.card {
        mygoose::column(c, mygoose::Box { width: 160.0, height: 70.0, padding: 12.0, background: 0xf4f4f5, radius: 8.0,
            shadow: if s.shadow { mygoose::Shadow { blur: 10.0, spread: 2.0, x: -4.0, y: 5.0, opacity: 0.4 } } else { mygoose::Shadow {} } });
        mygoose::text(c, "Shadow card"); mygoose::end(c);
    }
    mygoose::end(c); mygoose::end(c);
}
fn select_frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: SelectState&) {
    mygoose::build_frame(c, s, 400.0, 400.0, select_view);
    test_support::paint_checked(c, cache);
}
fn select_event(c: mygoose::Context&, cache: mygoose::SceneCache&, s: SelectState&, e: mygoose::Event) {
    mygoose::send(c, e); select_frame(c, cache, s);
}
fn select_click(c: mygoose::Context&, cache: mygoose::SceneCache&, s: SelectState&, r: mygoose::Rect) {
    let x = r.x + r.w * 0.5; let y = r.y + r.h * 0.5;
    select_event(c, cache, s, mygoose::Event { kind: 2, x: x, y: y });
    select_event(c, cache, s, mygoose::Event { kind: 3, x: x, y: y });
}
fn native_input_cases() {
    var s = State {}; var c = mygoose::Context {};
    mygoose::build_frame(c, s, 400.0, 400.0, view);
    let input = mygoose::find_node(c, "input"); assert(input >= 0); mygoose::focus(c, c.nodes[input].id);
    mygoose::send_native(c, 10);
    assert(c.event.kind == 10 && c.ime.active && c.ime.owner == c.focus && c.ime.text.len == 0);
    mygoose::send_native(c, 11);
    assert(c.event.kind == 11 && !c.ime.active && c.ime.owner == c.focus);
    c.widths[0] = mygoose::WidthEntry { hash: 1, width: 23.0 }; c.force = false;
    mygoose::send_native(c, 0);
    assert(c.event.kind == 0 && !c.force && c.widths[0].hash == 1);
    let inc = mygoose::find(c, "inc");
    mygoose::send(c, mygoose::Event { kind: 2, x: inc.x + 1.0, y: inc.y + 1.0 }); assert(c.active != 0);
    mygoose::send_native(c, 8);
    assert(c.event.kind == 8 && c.force && c.active == 0 && c.pointer.reason == mygoose::cancel_resize);
    for entry in c.widths { assert(entry.hash == 0); }
    mygoose::focus(c, c.nodes[input].id); mygoose::composition(c, "候補", 3, 0, 6);
    mygoose::send_native(c, 7);
    assert(c.event.kind == 7 && c.focus == 0 && !c.ime.active && c.ime.text.len == 0);
    print("PASS: shared native event ingestion, preedit/commit, resize cache/capture invalidation and blur cleanup\n");
}
fn main() {
    run_scroll_cases();
    animation_clocks(); pacing(); paced_input();
    mygoose::headless_open(400, 400); native_input_cases();
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {}; var s = State {};
    run_damage_cases(c, cache); c = mygoose::Context {}; cache = mygoose::SceneCache {};
    run_button_cases(c, cache); c = mygoose::Context {}; cache = mygoose::SceneCache {};
    assert(frame(c, cache, s)); assert(!frame(c, cache, s));
    assert(c.paints == 2); assert(c.count < 40); assert(s.range.first == 0 && s.range.end == 7);
    let inc = mygoose::find(c, "inc"); assert(inc.x == 10.0 && inc.y == 10.0 && inc.h == 34.0);
    click(c, cache, s, "inc"); assert(s.count == 1);
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_enter }); assert(s.count == 2);
    s.enabled = false; frame(c, cache, s); click(c, cache, s, "inc"); assert(s.count == 2);
    click(c, cache, s, "check"); assert(s.checked);
    click(c, cache, s, "check"); assert(!s.checked);
    click(c, cache, s, "slider"); assert(s.volume >= 49.0 && s.volume <= 51.0);
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_right }); assert(s.volume == 51.0);
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_end }); assert(s.volume == 100.0);
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_tab });
    let input_id = c.focus; assert(input_id != 0);
    event(c, cache, s, mygoose::Event { kind: 6, code: 65 });
    event(c, cache, s, mygoose::Event { kind: 6, code: 0x65e5 });
    event(c, cache, s, mygoose::Event { kind: 6, code: 0x1f680 });
    assert(s.input.bytes == "A日🚀"); assert(s.input.cursor == 8);
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_backspace }); assert(s.input.bytes == "A日");
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_left, shift: true });
    event(c, cache, s, mygoose::Event { kind: 6, code: 66 }); assert(s.input.bytes == "AB");
    event(c, cache, s, mygoose::Event { kind: 5, code: 65, ctrl: true });
    event(c, cache, s, mygoose::Event { kind: 6, code: 0x03bb }); assert(s.input.bytes == "λ");
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_home });
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_delete }); assert(s.input.bytes.len == 0);
    // Preedit replaces the selection visually, without touching the document.
    mygoose::insert_text(s.input, "abCDxy"); s.input.anchor = 2; s.input.cursor = 4;
    mygoose::composition(c, "日本🚀", 6, 0, 6); frame(c, cache, s);
    assert(s.input.bytes == "abCDxy" && s.input.cursor == 4 && s.input.anchor == 2);
    var preview_found = false;
    for i: i32 in c.count { let n .= c.nodes[i]; if n.kind == 8 {
        assert(mygoose::node_text(c, i) == "ab日本🚀xy");
        assert(n.composition_w > n.target_w && n.target_w > 0.0 && n.ime_owner == c.focus);
        preview_found = true;
    } } assert(preview_found);
    // Display ticks must preserve preedit; event 12 remains IME cancellation.
    event(c, cache, s, mygoose::Event { kind: mygoose::event_frame });
    assert(c.ime.active && c.ime.text == "日本🚀" && s.input.bytes == "abCDxy");
    // IME consumes editing keys while composing; cancellation restores selection.
    event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_backspace }); assert(s.input.bytes == "abCDxy");
    event(c, cache, s, mygoose::Event { kind: 12 }); assert(s.input.bytes == "abCDxy" && s.input.anchor == 2);
    mygoose::composition(c, "日本", 6, 0, 6, true); frame(c, cache, s);
    assert(s.input.bytes == "ab日本xy" && s.input.cursor == 8 && s.input.anchor == 8);
    frame(c, cache, s); assert(s.input.bytes == "ab日本xy"); // no duplicate commit on rebuild
    s.input.anchor = 0; s.input.cursor = s.input.bytes.len; mygoose::erase_selection(s.input);
    // Invalid scalars must leave both content and selection intact.
    assert(!mygoose::insert_scalar(s.input, 0xd800)); assert(!mygoose::insert_scalar(s.input, 0x110000));
    var full: u8[4096] = ['x'; 4096]; assert(mygoose::insert_text(s.input, full));
    assert(!mygoose::insert_scalar(s.input, 0x65e5)); assert(s.input.bytes.len == 4096);
    s.input.anchor = 0; assert(mygoose::insert_text(s.input, "ok")); assert(s.input.bytes == "ok");
    let list = mygoose::find(c, "list");
    event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 10.0, y: list.y + 10.0, delta: -12.5, scroll_pixels: true });
    assert(s.scroll.offset == 12.5);
    event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 10.0, y: list.y + 10.0, delta: -0.25, scroll_pixels: true });
    assert(s.scroll.offset == 12.75);
    event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 10.0, y: list.y + 10.0, delta: 12.75, scroll_pixels: true });
    assert(s.scroll.offset == 0.0);
    event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 10.0, y: list.y + 10.0, delta: -1.0 });
    assert(s.scroll.offset == 60.0); // Ordinary wheel detents still move three rows.
    event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 10.0, y: list.y + 10.0, delta: -1000000.0 });
    assert(s.range.end == 10000 && s.range.first == 9995); assert(c.count < 40);
    // Wheel events outside the viewport cannot scroll the list.
    event(c, cache, s, mygoose::Event { kind: 4, x: 399.0, y: 399.0, delta: 10.0 }); assert(s.range.first == 9995);
    s.rows = 0; frame(c, cache, s); assert(s.range.first == 0 && s.range.end == 0 && s.scroll.offset == 0.0);
    click(c, cache, s, "remove"); assert(!s.show); assert(c.focus == 0);
    // Releasing outside the pressed control must not activate it.
    s.enabled = true; frame(c, cache, s);
    event(c, cache, s, mygoose::Event { kind: 2, x: inc.x + 2.0, y: inc.y + 2.0 });
    event(c, cache, s, mygoose::Event { kind: 3, x: 399.0, y: 399.0 }); assert(s.count == 2);
    event(c, cache, s, mygoose::Event { kind: 7 }); assert(c.active == 0 && c.focus == 0);
    assert(!frame(c, cache, s));
    // Flex growth distributes spare width in proportion to weight.
    mygoose::begin(c, 400.0, 100.0);
    mygoose::row(c, mygoose::Box { fill: true, gap: 10.0 });
    mygoose::column(c, mygoose::Box { grow: 1.0 }, "a"); mygoose::end(c);
    mygoose::column(c, mygoose::Box { grow: 2.0 }, "b"); mygoose::end(c);
    mygoose::end(c); mygoose::finish(c);
    let a = mygoose::find(c, "a"); let b = mygoose::find(c, "b");
    assert(a.w == 130.0 && b.w == 260.0 && b.x == 140.0);
    assert(mygoose::intersect(mygoose::Rect { 0.0, 0.0, 10.0, 10.0 }, mygoose::Rect { 5.0, 5.0, 20.0, 20.0 }).w == 5.0);
    mygoose::insert_text(s.doc, "one\n日本語\nthree");
    area_event(c, cache, s, mygoose::Event {});
    mygoose::click(c, s, "doc", area_view); if mygoose::damage(c, cache) { mygoose::paint(c); }
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_home, ctrl: true }); assert(s.doc.cursor == 0);
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_down }); assert(s.doc.cursor == 4);
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_right }); assert(s.doc.cursor == 7);
    mygoose::composition(c, "かな", 3, 0, 3);
    area_event(c, cache, s, c.event); assert(s.doc.bytes == "one\n日本語\nthree");
    var inline_found = false;
    for i: i32 in c.count { let n .= c.nodes[i]; if n.ime_owner == c.focus && n.composition_w > 0.0 {
        assert(mygoose::node_text(c, i) == "日かな本語"); assert(n.target_w > 0.0); inline_found = true;
    } } assert(inline_found);
    // Cancelling preedit must not remove the character before it.
    area_event(c, cache, s, mygoose::Event { kind: 12 }); assert(s.doc.cursor == 7);
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_enter }); assert(s.doc.bytes == "one\n日\n本語\nthree");
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_backspace }); assert(s.doc.bytes == "one\n日本語\nthree");
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_end, ctrl: true });
    for j in 30 { area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_enter }); }
    assert(s.doc.scroll > 0.0 && c.count < 20);
    let before_scroll = s.doc.scroll;
    area_event(c, cache, s, mygoose::Event { kind: 4, x: 20.0, y: 20.0, delta: 12.5, scroll_pixels: true });
    assert(s.doc.scroll == before_scroll - 12.5);
    mygoose::composition(c, "変換中", 9, 0, 6); area_event(c, cache, s, c.event);
    assert(c.ime.active && s.doc.scroll > 0.0);
    if mygoose::mg_dump_requested() { assert(mygoose::mg_dump()); }
    mygoose::composition(c, "変換", 6, 0, 6, true); area_event(c, cache, s, c.event);
    assert(s.doc.bytes[s.doc.bytes.len - 6..] == "変換");
    area_event(c, cache, s, mygoose::Event { kind: 5, code: 65, ctrl: true });
    area_event(c, cache, s, mygoose::Event { kind: 6, code: 90 }); assert(s.doc.bytes == "Z"); assert(s.doc.scroll == 0.0);
    // Very long lines must keep document bytes without overflowing frame text.
    s.doc.anchor = 0; var long_line: u8[65536] = ['x'; 65536]; assert(mygoose::insert_text(s.doc, long_line));
    area_event(c, cache, s, mygoose::Event {}); assert(c.text_count < 1024 && s.doc.window_start > 0);
    area_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_home }); assert(s.doc.window_start == 0);
    let old_pixels = mygoose::mg_pixel_hash(); c.theme.accent = 0xff0000;
    area_event(c, cache, s, mygoose::Event {}); assert(mygoose::mg_pixel_hash() != old_pixels);
    var dropdown = SelectState {};
    mygoose::send(c, mygoose::Event { kind: 7 }); select_frame(c, cache, dropdown);
    let closed_pixels = mygoose::mg_pixel_hash();
    select_click(c, cache, dropdown, mygoose::find(c, "select"));
    assert(c.popup != 0 && c.count < 20 && c.popup_rows == 5 && dropdown.selected == 0);
    if mygoose::mg_dump_requested() { assert(mygoose::mg_dump()); }
    let owner = c.popup;
    assert(mygoose::option_rect(c, 3).y > c.popup_anchor.y + 40.0);
    select_click(c, cache, dropdown, mygoose::option_rect(c, 3));
    assert(dropdown.selected == 3 && c.popup == 0 && dropdown.presses == 0 && c.focus == owner);
    select_event(c, cache, dropdown, mygoose::Event { kind: 5, code: mygoose::key_space }); assert(c.popup != 0);
    select_event(c, cache, dropdown, mygoose::Event { kind: 5, code: mygoose::key_end }); assert(c.popup_highlight == 19 && c.popup_first == 15);
    select_event(c, cache, dropdown, mygoose::Event { kind: 5, code: mygoose::key_enter }); assert(dropdown.selected == 19 && c.popup == 0);
    select_click(c, cache, dropdown, mygoose::find(c, "select"));
    select_event(c, cache, dropdown, mygoose::Event { kind: 4, x: c.popup_rect.x + 10.0, y: c.popup_rect.y + 10.0, delta: 1000.0 });
    assert(c.popup_first == 0 && dropdown.selected == 19);
    for i in 3 {
        select_event(c, cache, dropdown, mygoose::Event { kind: 4, x: c.popup_rect.x + 10.0, y: c.popup_rect.y + 10.0, delta: -7.5, scroll_pixels: true });
        assert(c.popup_first == 0);
    }
    select_event(c, cache, dropdown, mygoose::Event { kind: 4, x: c.popup_rect.x + 10.0, y: c.popup_rect.y + 10.0, delta: -7.5, scroll_pixels: true });
    assert(c.popup_first == 1); // Four small gestures accumulate one 30-point row.
    select_event(c, cache, dropdown, mygoose::Event { kind: 5, code: mygoose::key_escape }); assert(c.popup == 0 && dropdown.selected == 19);
    select_click(c, cache, dropdown, mygoose::find(c, "select"));
    select_event(c, cache, dropdown, mygoose::Event { kind: 5, code: mygoose::key_tab }); assert(c.popup == 0 && c.focus != owner);
    select_click(c, cache, dropdown, mygoose::find(c, "select"));
    // Outside-click dismissal consumes the click instead of pressing the button underneath.
    let under = mygoose::find(c, "under");
    select_click(c, cache, dropdown, mygoose::Rect { 340.0, under.y, 10.0, under.h });
    assert(c.popup == 0 && dropdown.presses == 0);
    select_click(c, cache, dropdown, mygoose::Rect { 340.0, under.y, 10.0, under.h }); assert(dropdown.presses == 1);
    dropdown.disabled = true; select_frame(c, cache, dropdown);
    select_click(c, cache, dropdown, mygoose::find(c, "select")); assert(c.popup == 0);
    dropdown.disabled = false; dropdown.empty = true; select_frame(c, cache, dropdown); assert(dropdown.selected == -1);
    select_click(c, cache, dropdown, mygoose::find(c, "select")); assert(c.popup == 0);
    dropdown.empty = false; dropdown.selected = 0; dropdown.bottom = true; select_frame(c, cache, dropdown);
    select_click(c, cache, dropdown, mygoose::find(c, "select")); assert(c.popup_rect.y < c.popup_anchor.y);
    dropdown.show = false; select_frame(c, cache, dropdown); assert(c.popup == 0);
    dropdown.bottom = false; dropdown.show = true; select_frame(c, cache, dropdown);
    dropdown.card_offset = 40.0; select_frame(c, cache, dropdown);
    assert(mygoose::mg_pixel_hash() != closed_pixels);
    dropdown.shadow = false; select_frame(c, cache, dropdown);
    dropdown.card = false; select_frame(c, cache, dropdown);
    assert(!mygoose::damage(c, cache));
    run_text_edit_cases(c, cache);
    run_block_cases(c, cache);
    run_table_cases(c, cache);
    run_interaction_cases(c, cache);
    run_selection_cases(c, cache);
    mygoose::mg_close(); print("PASS: layout, controls, dropdowns, shadows, UTF-8 editing, inline IME, focus, clipping, virtualization and damage");
}
