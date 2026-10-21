import test_support from "../../tests";
import mygoose_charts from "../../extras/charts";
import monitor from ".";
import mygoose from "../../src";
import mygoose_graphics from "../../extras/graphics";
import mygoose_images from "../../extras/images";
import mygoose_window from "../../extras/window";
import std;
import os;

struct CaptionCase { presses: i32[3] = [0; 3] }
let caption_keys: const u8[:][3] = ["window-minimize", "window-maximize", "window-close"];
fn caption_case_view(s: CaptionCase&, c: mygoose::Context&) {
    mygoose::row(c) {
        for kind: i32 in 3 { if mygoose_window::control(c, kind, caption_keys[kind]) { s.presses[kind] += 1; } }
    };
}
fn caption_case_frame(s: CaptionCase&, c: mygoose::Context&, cache: mygoose::SceneCache&) {
    mygoose::build_frame(c, s, 400.0, 400.0, caption_case_view);
    test_support::paint_checked(c, cache, mygoose::monitor_paint);
}
fn caption_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = CaptionCase {}; caption_case_frame(s, c, cache);
    for kind: i32 in 3 {
        let button = mygoose::find_node(c, caption_keys[kind]); assert(button >= 0);
        let glyph = c.nodes[button].first;
        assert(button >= 0 && glyph >= 0);
        let id = c.nodes[button].id; let r = c.nodes[glyph].rect;
        // Center and both sides of the actual vector glyph must target its button.
        for fraction in [0.25, 0.5, 0.75] {
            let x = r.x + r.w * fraction as! f32; let y = r.y + r.h * 0.5;
            mygoose::send(c, mygoose::Event { kind: 1, x: x, y: y }); caption_case_frame(s, c, cache);
            assert(c.hot == id && c.nodes[button].background == (if kind == 2 { 0xe81123 } else { 0x303033 }));
            mygoose::send(c, mygoose::Event { kind: 2, x: x, y: y }); caption_case_frame(s, c, cache);
            assert(c.active == id && c.focus == id && c.nodes[button].background == (if kind == 2 { 0xb50d1b } else { 0x454548 }));
            let before = s.presses[kind];
            mygoose::send(c, mygoose::Event { kind: 3, x: x, y: y }); caption_case_frame(s, c, cache);
            assert(s.presses[kind] == before + 1 && c.active == 0);
        }
    }
    for presses in s.presses { assert(presses == 3); }
    print("PASS: caption glyph hover, press, focus, activation and partial/full pixels\n");
}
fn first_process_rect(c: mygoose::Context&) -> mygoose::Rect {
    for i: i32 in c.count {
        let n .= c.nodes[i];
        if n.kind == mygoose::kind_selectable_row && n.box.height == 28.0 && n.rect.w > 300.0 {
            let visible = mygoose::intersect(n.rect, n.clip_rect); if visible.h > 0.0 { return visible; }
        }
    }
    assert(false); mygoose::Rect {}
}
fn select_at(c: mygoose::Context&, s: mygoose::Monitor&, fraction: f32) {
    let r = first_process_rect(c); let x = r.x + r.w * fraction; let y = r.y + r.h * 0.5;
    mygoose::send(c, mygoose::Event { kind: 2, x: x, y: y }); mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    mygoose::send(c, mygoose::Event { kind: 3, x: x, y: y }); mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
}
fn control_disabled(c: mygoose::Context&, key: const u8[:]) -> bool {
    let i = mygoose::find_node(c, key); assert(i >= 0 && c.nodes[i].kind == 3); c.nodes[i].disabled
}
fn many_cores(s: mygoose::Monitor&, c: mygoose::Context&) {
    c.theme = mygoose::monitor_theme();
    mygoose::monitor_cpu(s, c, c.width, 128);
}
fn check_columns(c: mygoose::Context&, compact: bool) {
    let full: const u8[:][7] = ["sort-Name", "sort-CPU", "sort-GPU", "sort-Memory", "sort-Threads", "sort-CPU time", "sort-PID"];
    let small: const u8[:][7] = ["sort-Name", "sort-CPU", "sort-GPU", "sort-Memory", "sort-PID", "", ""];
    for i: i32 in c.count {
        let n .= c.nodes[i];
        if n.kind == mygoose::kind_selectable_row && n.box.height == 28.0 && n.rect.w > 300.0 {
            var cell = c.nodes[n.first].first;
            for slot: i32 in (if compact { 5 } else { 7 }) {
                let heading = mygoose::find(c, if compact { small[slot] } else { full[slot] });
                assert(cell >= 0);
                let r = c.nodes[cell].rect;
                assert(abs(r.x - heading.x) < 0.01 && abs(r.w - heading.w) < 0.01);
                let clip = c.nodes[cell].clip_rect;
                assert(clip.x >= n.rect.x && clip.x + clip.w <= n.rect.x + n.rect.w + 0.01);
                cell = c.nodes[cell].next;
            }
            assert(cell == -1); return;
        }
    }
    assert(false);
}
fn column_event(c: mygoose::Context&, s: mygoose::Monitor&, kind: i32, x: f32, y: f32) {
    mygoose::send(c, mygoose::Event { kind: kind, x: x, y: y });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
}
fn resize_columns(c: mygoose::Context&, s: mygoose::Monitor&, cache: mygoose::SceneCache&) {
    check_columns(c, false);
    let name = mygoose::find(c, "sort-Name"); let cpu = mygoose::find(c, "sort-CPU");
    let handle = mygoose::find(c, "resize-Name"); let x = handle.x + 4.0; let y = handle.y + 12.0;
    column_event(c, s, 1, x, y); assert(c.hot != 0);
    column_event(c, s, 2, x, y); assert(c.pointer.drag_owner != 0);
    column_event(c, s, 1, x - 80.0, y);
    assert(mygoose::find(c, "sort-Name").w == name.w - 80.0 && mygoose::find(c, "sort-CPU").w == cpu.w);
    assert(mygoose::find(c, "sort-CPU").x == cpu.x - 80.0);
    let shifted: const u8[:][4] = ["sort-Memory", "sort-Threads", "sort-CPU time", "sort-PID"];
    var positions: f32[4] = [0.0; 4]; var sizes: f32[4] = [0.0; 4];
    for i: i32 in 4 { let r = mygoose::find(c, shifted[i]); positions[i] = r.x; sizes[i] = r.w; }
    check_columns(c, false);
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    let partial = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(partial == mygoose::mg_pixel_hash());
    // Release coordinates count even when there was no final motion event.
    column_event(c, s, 3, x - 92.0, y);
    assert(c.pointer.drag_owner == 0 && mygoose::find(c, "sort-CPU").w == cpu.w && mygoose::find(c, "sort-CPU").x == cpu.x - 92.0);
    for i: i32 in 4 { let r = mygoose::find(c, shifted[i]); assert(r.x == positions[i] - 12.0 && r.w == sizes[i]); }
    assert(s.sort == 2 && !s.ascending && s.selected == -1);
    column_event(c, s, 1, 10.0, 500.0); assert(c.hot == 0);
    let preferred = s.table.preferred[0];
    mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view); check_columns(c, true);
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); check_columns(c, false);
    assert(s.table.preferred[0] == preferred && mygoose::find(c, "sort-Name").w == preferred);
    let second = mygoose::find(c, "resize-CPU"); let bx = second.x + 4.0;
    column_event(c, s, 2, bx, y); column_event(c, s, 1, 100000.0, y);
    assert(mygoose::find(c, "sort-CPU").w == 4096.0 && mygoose::find(c, "sort-Memory").w == sizes[0]); check_columns(c, false);
    column_event(c, s, 1, -100000.0, y);
    assert(mygoose::find(c, "sort-CPU").w == 42.0); check_columns(c, false);
    column_event(c, s, 7, 0.0, 0.0); assert(c.pointer.drag_owner == 0);
    let cancelled = s.table.preferred[1]; column_event(c, s, 1, bx, y); assert(s.table.preferred[1] == cancelled);
    // Focused dividers can be moved precisely without a mouse drag.
    let keyboard = mygoose::find(c, "resize-Name");
    column_event(c, s, 2, keyboard.x + 4.0, y); column_event(c, s, 3, keyboard.x + 4.0, y);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_left });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(s.table.preferred[0] == preferred - 8.0 && s.table.preferred[1] == cancelled);
    // Widen CPU without changing Memory or other column widths, then scroll
    // both headers and rows together to reach the off-screen suffix.
    let grow = mygoose::find(c, "resize-CPU");
    column_event(c, s, 2, grow.x + 4.0, y); column_event(c, s, 3, grow.x + 244.0, y);
    assert(s.table.preferred[1] == cancelled + 240.0 && s.table.preferred[2] == sizes[0]);
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    let scrollbar = mygoose::find(c, "process-horizontal");
    let sx = scrollbar.x + scrollbar.w - 2.0; let sy = scrollbar.y + 6.0;
    let unscrolled = mygoose::find(c, "sort-CPU");
    column_event(c, s, 2, sx, sy); column_event(c, s, 3, sx, sy);
    assert(s.table.offset > 0.0 && mygoose::find(c, "sort-CPU").x < unscrolled.x); check_columns(c, false);
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    let scrolled = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(scrolled == mygoose::mg_pixel_hash());
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_home });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(s.table.offset == 0.0);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_end });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    let last = mygoose::find(c, "resize-PID"); let last_width = s.table.preferred[5];
    column_event(c, s, 2, last.x + 4.0, y); column_event(c, s, 3, last.x + 24.0, y);
    assert(s.table.preferred[5] == last_width + 20.0); check_columns(c, false);
    s.table.offset = 0.0; mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    let resized = s.table.preferred[1];
    mygoose::click(c, s, "sort-CPU", mygoose::monitor_view); assert(s.table.preferred[1] == resized);
    mygoose::monitor_select(s, 0); mygoose::build_frame(c, s, 900.0, 640.0, mygoose::monitor_view);
    check_columns(c, true); assert(s.table.preferred[1] == resized);
    s.selected = -1; s.sort = 2; s.ascending = false;
    s.table.preferred = [0.0; 32]; s.table.offset = 0.0;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
}

fn search_focus_cases(c: mygoose::Context&, s: mygoose::Monitor&) {
    let field = mygoose::find(c, "process-search");
    var shell: i32 = -1; var input: i32 = -1; var glyph = mygoose::Rect {};
    for i: i32 in c.count { if c.nodes[i].focus_target != 0 { shell = i; } }
    assert(shell >= 0 && mygoose::interactive(c.nodes[shell]) && !mygoose::focusable(c.nodes[shell]));
    let owner = c.nodes[shell].focus_target;
    for i: i32 in c.count { if c.nodes[i].id == owner { input = i; } }
    assert(input > shell);
    for i: i32 in shell + 1..input { if c.nodes[i].kind == mygoose::kind_canvas { glyph = c.nodes[i].rect; } }
    assert(glyph.w > 0.0);
    let edit = c.nodes[input].rect;
    let points: mygoose::Rect[4] = [
        mygoose::Rect { x: glyph.x + glyph.w * 0.5, y: glyph.y + glyph.h * 0.5 },
        mygoose::Rect { x: field.x + field.w * 0.5, y: field.y + 0.5 },
        mygoose::Rect { x: field.x + field.w - 4.0, y: field.y + field.h * 0.5 },
        mygoose::Rect { x: edit.x + edit.w - 12.0, y: edit.y + edit.h * 0.5 }
    ];
    for p in points {
        mygoose::focus(c, 0);
        mygoose::send(c, mygoose::Event { kind: 2, x: p.x, y: p.y });
        mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.focus == owner);
        mygoose::send(c, mygoose::Event { kind: 3, x: p.x, y: p.y });
        mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.active == 0);
    }
    mygoose::send(c, mygoose::Event { kind: 6, code: 113 });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(s.search.bytes == "q");
    mygoose::click(c, s, "clear", mygoose::monitor_view); assert(s.search.bytes.len == 0 && c.focus == owner);
    s.search.bytes.append("keep text"); s.search.anchor = 2; s.search.cursor = 6;
    mygoose::composition(c, "候補", 3, 0, 6, false);
    for width in [700.0, 1240.0] {
        mygoose::build_frame(c, s, width as! f32, 820.0, mygoose::monitor_view);
        assert(c.focus == owner && c.ime.active && c.ime.owner == owner);
        assert(s.search.bytes == "keep text" && s.search.anchor == 2 && s.search.cursor == 6);
    }
    // IME owns Escape during preedit; afterward Escape clears, then dismisses.
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.ime.active && s.search.bytes == "keep text");
    mygoose::send(c, mygoose::Event { kind: 12 });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(s.search.bytes.len == 0 && c.focus == owner);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.focus == 0);
    s.page = 0; s.search.bytes.append("filter");
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    mygoose::send(c, mygoose::Event { kind: 5, code: 70, ctrl: true });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(s.page == 1 && c.focus == owner && s.search.anchor == 0 && s.search.cursor == 6);
    mygoose::click(c, s, "clear", mygoose::monitor_view);
}
fn menu_click(c: mygoose::Context&, s: mygoose::Monitor&, index: i64) {
    let r = mygoose::option_rect(c, index); let x = r.x + r.w * 0.5; let y = r.y + r.h * 0.5;
    column_event(c, s, 2, x, y); column_event(c, s, 3, x, y);
}
fn process_menu_cases(c: mygoose::Context&, s: mygoose::Monitor&, cache: mygoose::SceneCache&) {
    let r = first_process_rect(c);
    mygoose::send(c, mygoose::Event { kind: 14, x: r.x + 60.0, y: r.y + 14.0 });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(c.popup != 0 && c.popup_menu && s.selected >= 0 && !s.show_inspector);
    let pid = s.selected; let birth = s.selected_birth;
    mygoose::open_context_menu(c, s.selection.owner, c.width - 1.0, c.height - 1.0);
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(c.popup_rect.x + c.popup_rect.w <= c.width && c.popup_rect.y + c.popup_rect.h <= c.height);
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    let partial = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(partial == mygoose::mg_pixel_hash());
    menu_click(c, s, 6);
    var copied: u8[128] = [0; 128]; let length = mygoose::mg_clipboard_get(copied);
    assert(copied[..length] == mygoose::mon_format(pid as! f64, 0) && c.popup == 0 && s.selected_birth == birth);
    mygoose::send(c, mygoose::Event { kind: 5, code: 93 });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.popup != 0);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_end });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.popup_highlight == 9 && s.selected == pid);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_enter });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(c.popup == 0 && s.search.bytes == s.selected_name && s.visible > 0);
    mygoose::click(c, s, "clear", mygoose::monitor_view); mygoose::focus(c, s.selection.owner, true);
    mygoose::send(c, mygoose::Event { kind: 5, code: 121, shift: true });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.popup != 0);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); assert(c.popup == 0 && s.selected == pid);
    mygoose::open_context_menu(c, s.selection.owner, r.x, r.y);
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    column_event(c, s, 2, c.width - 12.0, c.height - 12.0); assert(c.popup == 0);
    column_event(c, s, 3, c.width - 12.0, c.height - 12.0);
    mygoose::open_context_menu(c, s.selection.owner, r.x, r.y);
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view); menu_click(c, s, 3);
    assert(s.show_inspector && c.popup == 0 && mygoose::find(c, "close-process").w > 0.0);
    // A context request keeps the inspector open, and uses the hovered row
    // rather than reapplying the list's previous selection index.
    s.scroll.offset = 0.0; mygoose::monitor_select(s, 0);
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    let first = first_process_rect(c); let first_pid = s.selected;
    column_event(c, s, 14, first.x + 60.0, first.y + 14.0);
    assert(c.popup != 0 && s.selected == first_pid && s.show_inspector && mygoose::find(c, "close-process").w > 0.0);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(s.visible > 1);
    let second_pid = mygoose::mon_process_value(1, 0) as! i64;
    let second_birth = mygoose::mon_process_birth(1);
    column_event(c, s, 1, first.x + 60.0, first.y + 42.0);
    column_event(c, s, 14, first.x + 60.0, first.y + 42.0);
    assert(c.popup != 0 && s.selected == second_pid && s.selected_birth == second_birth && s.show_inspector);
    assert(mygoose::find(c, "close-process").w > 0.0);
    menu_click(c, s, 6);
    let second_length = mygoose::mg_clipboard_get(copied);
    assert(copied[..second_length] == mygoose::mon_format(second_pid as! f64, 0));
    mygoose::focus(c, s.selection.owner, true);
    mygoose::send(c, mygoose::Event { kind: 5, code: 93 });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    assert(c.popup != 0 && s.selected == second_pid && s.show_inspector);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    mygoose::click(c, s, "close-process", mygoose::monitor_view);
    mygoose::monitor_select(s, 0, false);
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
    let closed = first_process_rect(c);
    column_event(c, s, 14, closed.x + 60.0, closed.y + 42.0);
    assert(c.popup != 0 && s.selected == second_pid && !s.show_inspector);
    menu_click(c, s, 6);
    s.selected = -1;
    mygoose::build_frame(c, s, c.width, c.height, mygoose::monitor_view);
}
fn toolbar_view(s: mygoose::Monitor&, c: mygoose::Context&) {
    c.theme = mygoose::monitor_theme(); mygoose::monitor_caption(s, c, c.width);
}
fn toolbar_layout_cases() {
    var s = mygoose::Monitor {}; var c = mygoose::Context {};
    let frames: mygoose_window::Frame[3] = [mygoose_window::Frame {}, mygoose_window::Frame { custom: true }, mygoose_window::Frame { custom: true, native: true }];
    let widths: f32[3] = [546.0, 802.0, 1042.0]; let pages: i32[3] = [0, 1, 3];
    for frame in frames {
        s.frame = frame;
        for width in widths {
            for page in pages {
                s.page = page; s.paused = false;
                for paused in [false, true] {
                    s.paused = paused;
                    mygoose::build_frame(c, s, width, 100.0, toolbar_view);
                    let pause = mygoose::find_node(c, "pause"); assert(pause >= 0);
                    let r = c.nodes[pause].rect;
                    assert(r.w == 30.0 && r.h == 30.0);
                    let glyph = c.nodes[pause].first;
                    assert(glyph >= 0 && glyph == c.nodes[pause].last && c.nodes[glyph].kind == mygoose::kind_canvas);
                    let icon = c.nodes[glyph].rect;
                    assert(abs(icon.x + icon.w * 0.5 - r.x - r.w * 0.5) < 0.01);
                    assert(abs(icon.y + icon.h * 0.5 - r.y - r.h * 0.5) < 0.01);
                    let controls = mygoose_window::controls_width(s.frame);
                    if controls == 0.0 { assert(abs(width - r.x - r.w - 18.0) < 0.01); }
                    else {
                        let close = mygoose::find(c, "window-close"); let minimize = mygoose::find(c, "window-minimize");
                        assert(abs(close.x + close.w - width) < 0.01 && minimize.x - r.x - r.w >= 18.0);
                    }
                    let search = mygoose::find_node(c, "process-search");
                    if search >= 0 {
                        let q = c.nodes[search].rect; let toolbar = mygoose::find(c, "monitor-toolbar");
                        assert(q.w >= 140.0 && q.x + q.w <= toolbar.x - 5.99);
                    }
                    mygoose::click(c, s, "pause", toolbar_view); assert(s.paused != paused);
                    mygoose::send(c, mygoose::Event {});
                }
            }
        }
    }
    print("PASS: icon-only pause/resume, centered glyph, right inset, search fit and all caption styles at narrow/wide sizes\n");
}
fn main() {
    let dump = mygoose::mg_dump_requested();
    mygoose::headless_open(if dump { 1500 } else { 1240 }, if dump { 1160 } else { 820 }); mygoose::mon_sample();
    toolbar_layout_cases();
    var s = mygoose::Monitor {}; var c = mygoose::Context {}; var cache = mygoose::SceneCache {};
    mygoose_window::attach(s.frame, 700.0, 480.0);
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    mygoose_window::sync(s.frame, c);
    if s.frame.custom && !s.frame.native {
        assert(mygoose::find(c, "window-minimize").w == 46.0);
        let close = mygoose::find(c, "window-close"); assert(close.x + close.w == 1240.0 && close.y == 0.0);
        // Headless native commands have no window to close; activation remains testable.
        mygoose::click(c, s, "window-maximize", mygoose::monitor_view);
        mygoose::click(c, s, "window-minimize", mygoose::monitor_view);
        mygoose::click(c, s, "window-close", mygoose::monitor_view);
    }
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c);
    mygoose::mon_icons_wait();
    // Exercise a single live history point, including GDI's path handling.
    sleep_ms(150); assert(mygoose::mon_sample());
    for page: i32 in 8 {
        s.page = page;
        mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
        assert(c.count < 700 && c.text_count < 50000);
        if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
        let partial = mygoose::mg_pixel_hash(); c.force = true;
        assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c);
        assert(partial == mygoose::mg_pixel_hash());
    }
    // The rich memory page scrolls as a whole, clamps after resizing, and
    // maintains the same result for incremental and complete painting.
    s.page = 3; s.memory_scroll.offset = 0.0;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(c.count < 700 && c.text_count < 30000);
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    let memory = mygoose::find(c, "memory-scroll");
    mygoose::send(c, mygoose::Event { kind: 4, x: memory.x + 100.0, y: memory.y + 100.0, delta: -2.0 });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.memory_scroll.offset > 0.0);
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c);
    let scrolled = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(scrolled == mygoose::mg_pixel_hash());
    s.memory_scroll.offset = 1000000.0;
    mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view);
    assert(s.memory_scroll.offset >= 0.0 && s.memory_scroll.offset <= s.memory_scroll.content - (640.0 - 106.0));
    s.memory_scroll.offset = 1000000.0;
    mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view);
    assert(s.memory_scroll.offset == s.memory_scroll.content - (640.0 - 106.0));
    let show_all = mygoose::find(c, "memory-show-all"); assert(show_all.y > 58.0 && show_all.y < 640.0);
    mygoose::click(c, s, "memory-show-all", mygoose::monitor_view); assert(s.page == 1 && s.sort == 2 && !s.ascending);
    s.page = 3; s.memory_scroll.offset = 180.0;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    let tile_pid = mygoose::mon_process_value(0, 0); let tile_key = mygoose::mon_format(tile_pid, 0);
    mygoose::click(c, s, tile_key, mygoose::monitor_view); assert(s.page == 1 && s.selected == tile_pid as! i64);
    s.selected = -1;
    // The first enabled collection establishes per-processor baselines.
    sleep_ms(150); assert(mygoose::mon_sample()); sleep_ms(150); assert(mygoose::mon_sample());
    s.page = 2; s.cpu_scroll.offset = 0.0;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(c.count < 700 && c.text_count < 50000);
    if mygoose::mon_core_count() > 0 && mygoose::mon_core_count() <= 24 {
        let last_core = mygoose::find(c, mygoose::mon_format((mygoose::mon_core_count() - 1) as f64,0));
        assert(last_core.y + last_core.h <= 796.0); // All 24 cores fit the default viewport.
    }
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    let cpu = mygoose::find(c, "cpu-scroll");
    mygoose::send(c, mygoose::Event { kind: 4, x: cpu.x + 100.0, y: cpu.y + 100.0, delta: -3.0 });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.cpu_scroll.offset > 0.0);
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c);
    let cpu_pixels = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(cpu_pixels == mygoose::mg_pixel_hash());
    // The same reusable rank rows open the matching process inspector.
    let busiest = mygoose::mon_process_value(0, 0); var cpu_key: u8[..64] = [];
    cpu_key.append("cpu-process-"); cpu_key.append(mygoose::mon_format(busiest,0));
    mygoose::click(c, s, cpu_key, mygoose::monitor_view); assert(s.page == 1 && s.sort == 1 && s.selected == busiest as! i64);
    s.page = 2; mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view);
    s.cpu_scroll.offset = 1000000.0; mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view);
    let all_cpu = mygoose::find(c, "cpu-show-all"); s.cpu_scroll.offset = max(0.0, s.cpu_scroll.offset + all_cpu.y - 140.0);
    mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view);
    mygoose::click(c, s, "cpu-show-all", mygoose::monitor_view); assert(s.page == 1 && s.sort == 1 && s.selected == -1);
    s.cpu_scroll.offset = 0.0;
    mygoose::build_frame(c, s, 1240.0, 820.0, many_cores); assert(c.count < 700 && c.text_count < 50000);
    mygoose::build_frame(c, s, 16384.0, 8192.0, many_cores); assert(c.count < 800 && c.text_count < 50000);
    sleep_ms(150); assert(mygoose::mon_sample()); s.page = 0;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    s.page = 1; s.sort = 2; s.ascending = false; mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    resize_columns(c, s, cache);
    let count = s.visible; assert(count > 0);
    mygoose::click(c, s, "sort-CPU", mygoose::monitor_view); assert(s.sort == 1 && !s.ascending);
    mygoose::click(c, s, "sort-CPU", mygoose::monitor_view); assert(s.ascending);
    s.search.bytes.append("__no_such_process__"); mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.visible == 0);
    mygoose::click(c, s, "clear", mygoose::monitor_view); assert(s.visible == count);
    assert(s.search.bytes.len == 0 && s.search.cursor == 0 && s.search.anchor == 0);
    var search_focused = false;
    for i: i32 in c.count { if c.nodes[i].kind == 8 && c.nodes[i].id == c.focus { search_focused = true; } }
    assert(search_focused);
    search_focus_cases(c, s);
    // Native caption clicks dismiss editing without erasing the filter.
    s.search.bytes.append("__search_focus__");
    mygoose::composition(c, "候補", 3, 0, 6, false);
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    mygoose::send(c, mygoose::Event { kind: 7 });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(c.focus == 0 && !c.ime.active && s.search.bytes == "__search_focus__");
    mygoose::send(c, mygoose::Event { kind: 6, code: 65 });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(s.search.bytes == "__search_focus__");
    s.search.bytes.clear(); mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    process_menu_cases(c, s, cache);
    // Every cell belongs to the same selectable row, with a stable identity.
    let first_pid = mygoose::mon_process_value(0, 0) as! i64;
    for fraction in [0.1, 0.6, 0.8, 0.99] {
        select_at(c, s, fraction as! f32); assert(s.selected == first_pid && s.selected_alive);
        assert(mygoose::find(c, "close-process").w > 0.0);
        if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
        let partial = mygoose::mg_pixel_hash(); c.force = true;
        assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(partial == mygoose::mg_pixel_hash());
    }
    let samples = s.selected_count;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.selected_count == samples);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_down });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(s.selected == mygoose::mon_process_value(1, 0) as! i64 && c.focus == s.selection.owner);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_up });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.selected == first_pid);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_end });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(s.selection.index == s.visible - 1 && s.selected == mygoose::mon_process_value(s.visible - 1, 0) as! i64);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_home });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(s.selected == first_pid && s.scroll.offset == 0.0 && c.focus == s.selection.owner);
    let birth = s.selected_birth;
    mygoose::click(c, s, "sort-Memory", mygoose::monitor_view); assert(s.selected == first_pid && s.selected_birth == birth);
    s.search.bytes.append("__no_such_process__");
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.visible == 0 && s.selected_alive);
    mygoose::click(c, s, "clear", mygoose::monitor_view);
    let own_pid = mygoose::mon_value(23);
    let matches = mygoose::mon_query(mygoose::mon_format(own_pid, 0), 0, true);
    for i: i32 in matches { if mygoose::mon_process_value(i, 0) == own_pid { mygoose::monitor_select(s, i); break; } }
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.selected_path.len > 0);
    assert(mygoose::find(c, "quit-process").w > 0.0 && mygoose::find(c, "force-quit-process").w > 0.0);
    assert(mygoose::find(c, "show-process-file").w == 40.0);
    assert(!control_disabled(c, "quit-process") && !control_disabled(c, "force-quit-process") && !control_disabled(c, "show-process-file"));
    // Opening a folder must not re-enable termination while Force Quit is pending.
    s.terminating = true; s.action = 3; s.action_result = 1;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(control_disabled(c, "quit-process") && control_disabled(c, "force-quit-process") && !control_disabled(c, "show-process-file"));
    s.terminating = false; s.action = 1; s.action_result = -3;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c);
    let message_pixels = mygoose::mg_pixel_hash(); c.force = true;
    assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(message_pixels == mygoose::mg_pixel_hash());
    s.action = 0; s.action_result = 0;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view);
    mygoose::click(c, s, "copy-path", mygoose::monitor_view); assert(s.copied);
    var copied: u8[4096] = [0; 4096]; let copied_length = mygoose::mg_clipboard_get(copied);
    assert(copied_length == s.selected_path.len);
    for i in copied_length { assert(copied[i] == s.selected_path[i]); }
    let actual_birth = s.selected_birth; s.selected_birth += 1; s.selected_epoch = -1;
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(!s.selected_alive);
    // Exited or unverified selections cannot dispatch termination from the UI.
    mygoose::click(c, s, "quit-process", mygoose::monitor_view);
    mygoose::click(c, s, "force-quit-process", mygoose::monitor_view); assert(s.action_result == 0);
    var no_target = mygoose::Monitor {};
    mygoose::monitor_process_action(no_target, 1); assert(no_target.action_result < 0);
    mygoose::monitor_process_action(no_target, 2); assert(no_target.action_result < 0 && !no_target.terminating);
    mygoose::monitor_process_action(no_target, 3); assert(no_target.action_result == -9);
    s.selected_birth = actual_birth; s.selected_epoch = -1;
    mygoose::build_frame(c, s, 900.0, 640.0, mygoose::monitor_view);
    let close = mygoose::find(c, "close-process"); assert(close.x + close.w <= 900.0 && close.y < 640.0);
    let details = mygoose::find(c, "process-details");
    if mygoose::damage(c, cache) { mygoose::monitor_paint(c); }
    mygoose::send(c, mygoose::Event { kind: 4, x: details.x + 100.0, y: details.y + 100.0, delta: -1.0 });
    mygoose::build_frame(c, s, 900.0, 640.0, mygoose::monitor_view); assert(s.detail_scroll.offset > 0.0);
    mygoose::build_frame(c, s, 700.0, 640.0, mygoose::monitor_view);
    assert(mygoose::find(c, "close-process").x < 700.0);
    mygoose_window::sync(s.frame, c);
    if s.frame.custom && !s.frame.native { let close = mygoose::find(c, "window-close"); assert(close.x + close.w == 700.0 && close.y == 0.0); }
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_escape });
    mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(s.selected == -1);
    select_at(c, s, 0.99); mygoose::click(c, s, "close-process", mygoose::monitor_view); assert(s.selected == -1);
    mygoose::click(c, s, "pause", mygoose::monitor_view); assert(s.paused);
    mygoose::click(c, s, "pause", mygoose::monitor_view); assert(!s.paused);
    mygoose::click(c, s, "5m", mygoose::monitor_view); assert(s.range == 300);
    s.scroll.offset = 2000.0; mygoose::build_frame(c, s, 1240.0, 820.0, mygoose::monitor_view); assert(c.count < 700);
    s.page = 0; s.scroll.offset = 0.0; mygoose::build_frame(c, s, 900.0, 640.0, mygoose::monitor_view); assert(c.count < 700);
    if mygoose::mg_dump_requested() {
        // Preview real counter intervals rather than the accelerated test cadence.
        sleep_ms(1000); assert(mygoose::mon_sample()); sleep_ms(1000); assert(mygoose::mon_sample());
        s.page = 2; s.cpu_scroll.offset = 0.0; s.scroll.offset = 0.0; s.sort = 1; s.ascending = false; s.range = 60;
        mygoose::build_frame(c, s, 1500.0, 1160.0, mygoose::monitor_view); mygoose::mon_icons_wait();
        mygoose::build_frame(c, s, 1500.0, 1160.0, mygoose::monitor_view); c.force = true;
        assert(mygoose::damage(c, cache)); mygoose::monitor_paint(c); assert(mygoose::mg_dump());
    }
    caption_cases(c, cache);
    mygoose::mon_icons_close(); mygoose::mon_close(); mygoose_window::detach(s.frame); mygoose::mg_close();
    print("PASS: monitor pages, independent columns/suffix movement/horizontal scroll/limits/cancel/keyboard/alignment, CPU grid/ranks/scroll/128-processor capacity, memory cards/scroll/tiles, row/cell selection, keyboard navigation, inspector/clipboard, virtualization and partial/full pixels\n");
}
