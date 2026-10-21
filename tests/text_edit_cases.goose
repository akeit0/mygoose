import .test_support;
import mygoose;
import std;

struct EditState {
    field: mygoose::TextInput = mygoose::TextInput {}, doc: mygoose::TextDocument = mygoose::TextDocument {}, password: bool = false
}
fn edit_view(s: EditState&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 12.0, gap: 12.0, align: 3 });
    mygoose::text_input(c, s.field, mygoose::InputOptions { width: 300.0, password: s.password, key: "field" });
    mygoose::text_area(c, s.doc, mygoose::AreaOptions { height: 220.0, key: "document" });
    mygoose::end(c);
}
fn edit_frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: EditState&) {
    mygoose::build_frame(c, s, 400.0, 400.0, edit_view);
    test_support::paint_checked(c, cache);
}
fn edit_event(c: mygoose::Context&, cache: mygoose::SceneCache&, s: EditState&, e: mygoose::Event) {
    mygoose::send(c, e); edit_frame(c, cache, s);
}
fn edit_key(c: mygoose::Context&, cache: mygoose::SceneCache&, s: EditState&, code: i32, ctrl: bool = false, shift: bool = false) {
    edit_event(c, cache, s, mygoose::Event { kind: 5, code: code, shift: shift, ctrl: ctrl });
}
fn clipboard_is(expected: const u8[:]) {
    var bytes: u8[65536] = [0; 65536]; let n = mygoose::mg_clipboard_get(bytes);
    assert(n == expected.len); assert(bytes[..n] == expected);
}
fn reset_field(s: EditState&, value: const u8[:], cursor: i64 = 0, anchor: i64 = 0) {
    s.field.bytes.clear(); s.field.bytes.append(value); s.field.cursor = cursor; s.field.anchor = anchor;
}
struct OversizeEdit { bytes: u8[..65537] = [], cursor: i64 = 0, anchor: i64 = 0 }
fn run_text_edit_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = EditState {}; reset_field(s, "hello 日本 world");
    mygoose::send(c, mygoose::Event { kind: 7 }); edit_frame(c, cache, s);
    let field = mygoose::find(c, "field"); let y = field.y + field.h * 0.5;
    let start = field.x + 8.0 + mygoose::text_width(c, "hello ", 14.0);
    let stop = field.x + 8.0 + mygoose::text_width(c, "hello 日本", 14.0);
    edit_event(c, cache, s, mygoose::Event { kind: 2, x: start, y: y, code: 1 });
    edit_event(c, cache, s, mygoose::Event { kind: 1, x: stop, y: y });
    edit_event(c, cache, s, mygoose::Event { kind: 3, x: stop, y: y });
    assert(s.field.anchor == 6 && s.field.cursor == 12);
    edit_key(c, cache, s, 67, true); clipboard_is("日本");
    edit_key(c, cache, s, 88, true); assert(s.field.bytes == "hello  world"); clipboard_is("日本");
    edit_key(c, cache, s, 86, true); assert(s.field.bytes == "hello 日本 world");
    edit_key(c, cache, s, 65, true); edit_key(c, cache, s, 45, true); clipboard_is("hello 日本 world");
    edit_key(c, cache, s, 46, false, true); assert(s.field.bytes.len == 0);
    edit_key(c, cache, s, 45, false, true); assert(s.field.bytes == "hello 日本 world");
    // Double-click a UTF-8 word; triple-click selects the whole input.
    edit_event(c, cache, s, mygoose::Event { kind: 2, x: (start + stop) * 0.5, y: y, code: 2 });
    edit_event(c, cache, s, mygoose::Event { kind: 3, x: stop, y: y });
    assert(s.field.anchor == 6 && s.field.cursor == 12);
    edit_key(c, cache, s, mygoose::key_left); assert(s.field.cursor == 6 && s.field.anchor == 6);
    s.field.anchor = 6; s.field.cursor = 12;
    edit_key(c, cache, s, mygoose::key_right); assert(s.field.cursor == 12 && s.field.anchor == 12);
    edit_event(c, cache, s, mygoose::Event { kind: 2, x: start, y: y, code: 3 });
    edit_event(c, cache, s, mygoose::Event { kind: 3, x: start, y: y }); assert(s.field.anchor == 0 && s.field.cursor == 18);
    edit_key(c, cache, s, mygoose::key_home);
    edit_key(c, cache, s, mygoose::key_right, true, true); assert(s.field.anchor == 0 && s.field.cursor == 6);
    edit_key(c, cache, s, 67, true); clipboard_is("hello ");
    edit_key(c, cache, s, mygoose::key_right, true); assert(s.field.cursor == 13);
    edit_key(c, cache, s, mygoose::key_backspace, true); assert(s.field.bytes == "hello world");
    reset_field(s, "hello 日本 world", 6, 6); edit_frame(c, cache, s);
    edit_key(c, cache, s, mygoose::key_delete, true); assert(s.field.bytes == "hello world");
    assert(mygoose::mg_clipboard_set("unchanged"));
    s.field.cursor = 0; s.field.anchor = 0;
    edit_key(c, cache, s, 67, true); edit_key(c, cache, s, 88, true); clipboard_is("unchanged");
    assert(s.field.bytes == "hello world");
    assert(mygoose::mg_clipboard_set("one\r\ntwo\rthree\n\tfour"));
    edit_key(c, cache, s, 65, true); edit_key(c, cache, s, 86, true); assert(s.field.bytes == "one two three  four");
    // Exact-capacity paste works; overflow and empty paste preserve selection.
    var capacity: u8[4096] = ['x'; 4096]; assert(mygoose::mg_clipboard_set(capacity));
    reset_field(s, ""); edit_key(c, cache, s, 86, true); assert(s.field.bytes.len == 4096);
    reset_field(s, "abc", 2, 1); edit_key(c, cache, s, 86, true); assert(s.field.bytes == "abc" && s.field.anchor == 1 && s.field.cursor == 2);
    assert(mygoose::mg_clipboard_set("")); edit_key(c, cache, s, 86, true); assert(s.field.bytes == "abc" && s.field.anchor == 1);
    // A rejected clipboard write must never turn Cut into Delete.
    var oversized = OversizeEdit {}; oversized.bytes.resize(65537, 'x'); oversized.cursor = 65537;
    assert(!mygoose::edit_keys(oversized, mygoose::Event { kind: 5, code: 88, ctrl: true })); assert(oversized.bytes.len == 65537);
    s.password = true; reset_field(s, "secret", 6, 0); edit_frame(c, cache, s);
    assert(mygoose::mg_clipboard_set("private clipboard"));
    edit_key(c, cache, s, 67, true); edit_key(c, cache, s, 88, true); clipboard_is("private clipboard"); assert(s.field.bytes == "secret");
    s.password = false;
    // Drag across lines and copy/cut/paste the selected UTF-8 bytes.
    s.doc.bytes.append("first\n日本\nlast"); edit_frame(c, cache, s);
    let doc = mygoose::find(c, "document"); let text_x = doc.x + 8.0 + 52.0;
    let from = text_x + mygoose::text_width(c, "fi", 14.0); let to = text_x + mygoose::text_width(c, "日本", 14.0);
    edit_event(c, cache, s, mygoose::Event { kind: 2, x: from, y: doc.y + 16.0, code: 1 });
    edit_event(c, cache, s, mygoose::Event { kind: 1, x: to, y: doc.y + 37.0 });
    edit_event(c, cache, s, mygoose::Event { kind: 3, x: to, y: doc.y + 37.0 });
    assert(s.doc.anchor == 2 && s.doc.cursor == 12);
    edit_key(c, cache, s, 67, true); clipboard_is("rst\n日本");
    edit_key(c, cache, s, 88, true); assert(s.doc.bytes == "fi\nlast");
    edit_key(c, cache, s, 86, true); assert(s.doc.bytes == "first\n日本\nlast");
    edit_event(c, cache, s, mygoose::Event { kind: 2, x: text_x + 5.0, y: doc.y + 37.0, code: 3 });
    edit_event(c, cache, s, mygoose::Event { kind: 3, x: text_x + 5.0, y: doc.y + 37.0 });
    assert(s.doc.anchor == 6 && s.doc.cursor == 13);
    edit_key(c, cache, s, 67, true); clipboard_is("日本\n");
    assert(mygoose::mg_clipboard_set("one\r\ntwo\rthree\n\tfour"));
    edit_key(c, cache, s, 65, true); edit_key(c, cache, s, 86, true); assert(s.doc.bytes == "one\ntwo\nthree\n\tfour");
    // A full 64 KiB document clipboard has no hidden extra-NUL requirement.
    var full: u8[65536] = ['z'; 65536]; assert(mygoose::mg_clipboard_set(full));
    edit_key(c, cache, s, 65, true); edit_key(c, cache, s, 86, true); assert(s.doc.bytes.len == 65536);
    print("PASS: mouse/word/line selection, Ctrl+A/C/X/V, clipboard aliases, UTF-8, capacity limits and password protection");
}
