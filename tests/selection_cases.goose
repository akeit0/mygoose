import .test_support;
import mygoose from "../src";
import std;

struct SelectionCase {
    selection: mygoose::ListSelection = mygoose::ListSelection {},
    scroll: mygoose::ScrollState = mygoose::ScrollState {},
    input: mygoose::TextInput = mygoose::TextInput {},
    total: i64 = 10000, start: i64 = 0, reverse: bool = false,
    generation: u64 = 0, disable_three: bool = false, disable_all: bool = false,
    show: bool = true, light: bool = false, visits: i64 = 0, activations: i64 = 0
}
fn selection_view(s: SelectionCase&, c: mygoose::Context&) {
    c.theme = if s.light { mygoose::light_theme() } else { mygoose::Theme {} };
    mygoose::column(c, mygoose::Box { width: 320.0, padding: 10.0, gap: 8.0 }) {
        mygoose::text_input(c, s.input, mygoose::InputOptions { key: "selection-input" });
        if s.show {
            fn item_at(index: i64) -> mygoose::ListItem {
                let id = s.start + (if s.reverse { s.total - 1 - index } else { index });
                mygoose::ListItem { id: id as u64, generation: s.generation,
                    disabled: s.disable_all || (s.disable_three && id == 3) }
            }
            s.visits = 0;
            mygoose::selectable_list(c, s.selection, s.scroll, s.total, 20.0,
                mygoose::Box { width: 300.0, height: 100.0 }, "selection-list", item_at) { index, item =>
                s.visits += 1;
                let activated = mygoose::selectable_row(c, s.selection, index, item,
                    mygoose::Box { width: 300.0, height: 20.0, padding: 2.0, clip: true }) { row =>
                    mygoose::text_number(c, item.id as i64);
                }; if activated { s.activations += 1; }
            };
        }
        mygoose::button(c, "After", mygoose::ButtonOptions { key: "selection-after" });
    };
}
fn selection_frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: SelectionCase&) {
    mygoose::build_frame(c, s, 400.0, 400.0, selection_view);
    assert(c.count < 40 && s.visits <= 7);
    test_support::paint_checked(c, cache);
}
fn selection_event(c: mygoose::Context&, cache: mygoose::SceneCache&, s: SelectionCase&, e: mygoose::Event) {
    mygoose::send(c, e); selection_frame(c, cache, s);
}
fn selection_key(c: mygoose::Context&, cache: mygoose::SceneCache&, s: SelectionCase&, key: i32, shift: bool = false) {
    selection_event(c, cache, s, mygoose::Event { kind: 5, code: key, shift: shift });
}
fn selection_node(c: mygoose::Context&, key: const u8[:]) -> u64 {
    let i = mygoose::find_node(c, key); assert(i >= 0); c.nodes[i].id
}
fn run_selection_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = SelectionCase {}; selection_frame(c, cache, s);
    mygoose::focus(c, 0);
    selection_key(c, cache, s, mygoose::key_tab);
    assert(c.focus == selection_node(c, "selection-input"));
    selection_key(c, cache, s, mygoose::key_tab); assert(c.focus == s.selection.owner);
    selection_key(c, cache, s, mygoose::key_tab); assert(c.focus == selection_node(c, "selection-after"));
    selection_key(c, cache, s, mygoose::key_tab, true); assert(c.focus == s.selection.owner);
    // One key moves once even when selection triggers a follow-up view build.
    selection_key(c, cache, s, mygoose::key_home); assert(s.selection.has_selection && s.selection.item.id == 0);
    selection_key(c, cache, s, mygoose::key_down); assert(s.selection.item.id == 1 && s.selection.index == 1);
    selection_key(c, cache, s, mygoose::key_up); assert(s.selection.item.id == 0);
    selection_key(c, cache, s, mygoose::key_up); assert(s.selection.item.id == 0);
    selection_key(c, cache, s, mygoose::key_end);
    assert(s.selection.item.id == 9999 && s.scroll.offset == 199900.0 && c.focus == s.selection.owner);
    selection_key(c, cache, s, mygoose::key_page_up); assert(s.selection.item.id == 9994);
    selection_key(c, cache, s, mygoose::key_page_down); assert(s.selection.item.id == 9999);
    selection_key(c, cache, s, mygoose::key_down); assert(s.selection.item.id == 9999);
    selection_key(c, cache, s, mygoose::key_enter); assert(s.activations == 1);
    selection_key(c, cache, s, mygoose::key_space); assert(s.activations == 2);
    // Wheel scrolling may hide the selected row without losing list focus.
    let list = mygoose::find(c, "selection-list");
    selection_event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 30.0, y: list.y + 30.0, delta: 5000.0 });
    assert(s.scroll.offset == 0.0 && c.focus == s.selection.owner && s.selection.item.id == 9999);
    selection_key(c, cache, s, mygoose::key_enter); assert(s.activations == 3 && s.scroll.offset == 199900.0);
    selection_event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 30.0, y: list.y + 30.0, delta: 5000.0 });
    selection_key(c, cache, s, mygoose::key_tab); assert(c.focus == selection_node(c, "selection-after"));
    selection_key(c, cache, s, mygoose::key_tab, true); assert(c.focus == s.selection.owner && s.scroll.offset == 199900.0);
    selection_event(c, cache, s, mygoose::Event { kind: 4, x: list.x + 30.0, y: list.y + 30.0, delta: 5000.0 });
    selection_key(c, cache, s, mygoose::key_up); assert(s.selection.item.id == 9998 && s.scroll.offset > 199000.0);
    // Sorting retains identity and the row's node ID, then reveals its new index.
    let stable_id = selection_node(c, "9998/0"); s.reverse = true; selection_frame(c, cache, s);
    assert(s.selection.item.id == 9998 && s.selection.index == 1 && s.scroll.offset == 20.0);
    assert(selection_node(c, "9998/0") == stable_id && c.focus == s.selection.owner);
    s.start = 20000; s.total = 10; selection_frame(c, cache, s);
    assert(s.selection.has_selection && s.selection.index == -1 && c.focus == s.selection.owner);
    s.start = 0; s.total = 10000; selection_frame(c, cache, s); assert(s.selection.index == 1);
    s.total = 0; selection_frame(c, cache, s);
    selection_key(c, cache, s, mygoose::key_end); assert(s.selection.item.id == 9998 && s.selection.index == -1);
    s.total = 10000; s.reverse = false; selection_frame(c, cache, s);
    // A reused ID never inherits the prior generation's selection.
    s.generation = 1; selection_frame(c, cache, s); assert(s.selection.index == -1 && s.selection.item.generation == 0);
    selection_key(c, cache, s, mygoose::key_home); assert(s.selection.item.id == 0 && s.selection.item.generation == 1);
    s.disable_three = true;
    selection_key(c, cache, s, mygoose::key_down); selection_key(c, cache, s, mygoose::key_down);
    selection_key(c, cache, s, mygoose::key_down); assert(s.selection.item.id == 4);
    selection_key(c, cache, s, mygoose::key_up); assert(s.selection.item.id == 2);
    let disabled = mygoose::find(c, "3/1");
    selection_event(c, cache, s, mygoose::Event { kind: 2, x: disabled.x + 10.0, y: disabled.y + 10.0 });
    selection_event(c, cache, s, mygoose::Event { kind: 3, x: disabled.x + 10.0, y: disabled.y + 10.0 });
    assert(s.selection.item.id == 2 && s.activations == 3);
    // A different control owns its keys; blur also stops list navigation.
    mygoose::click(c, s, "selection-input", selection_view);
    selection_key(c, cache, s, mygoose::key_end); assert(s.selection.item.id == 2);
    selection_event(c, cache, s, mygoose::Event { kind: 7 });
    selection_key(c, cache, s, mygoose::key_down); assert(s.selection.item.id == 2 && c.focus == 0);
    mygoose::focus(c, s.selection.owner, true); s.light = true; selection_frame(c, cache, s);
    selection_key(c, cache, s, mygoose::key_escape); assert(!s.selection.has_selection && c.focus == s.selection.owner);
    selection_key(c, cache, s, mygoose::key_down); assert(s.selection.item.id == 0);
    // Replacement while pressed cancels capture instead of selecting the new row.
    let first = mygoose::find(c, "0/1");
    selection_event(c, cache, s, mygoose::Event { kind: 2, x: first.x + 10.0, y: first.y + 10.0 }); assert(c.active != 0);
    s.generation = 2; selection_frame(c, cache, s); assert(c.active == 0 && c.focus == s.selection.owner);
    selection_event(c, cache, s, mygoose::Event { kind: 3, x: first.x + 10.0, y: first.y + 10.0 });
    assert(s.activations == 3 && s.selection.item.generation == 1);
    s.disable_all = true; selection_key(c, cache, s, mygoose::key_home); assert(s.selection.item.generation == 1);
    mygoose::clear_selection(s.selection); selection_key(c, cache, s, mygoose::key_end); assert(!s.selection.has_selection);
    s.show = false; selection_frame(c, cache, s); assert(c.focus == 0 && c.active == 0);
    print("PASS: shared list selection, stable identities/generations, single tab stop, arrows/page/home/end, disabled/empty/hidden rows, reveal, virtualization, focus/capture and partial/full pixels\n");
}
