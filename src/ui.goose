namespace mygoose;
import std;
import .geom;
import .damage;
import .scroll_motion;
import .frame;

// Fixed storage deliberately bounds memory and makes overflow explicit.
let max_nodes: i32 = 1024;
let max_text: i32 = 65536;
let key_tab: i32 = 9;
let key_enter: i32 = 13;
let key_space: i32 = 32;
let key_left: i32 = 37;
let key_up: i32 = 38;
let key_right: i32 = 39;
let key_down: i32 = 40;
let key_home: i32 = 36;
let key_end: i32 = 35;
let key_page_up: i32 = 33;
let key_page_down: i32 = 34;
let key_backspace: i32 = 8;
let key_delete: i32 = 46;
let key_escape: i32 = 27;
let cursor_arrow: i32 = 0;
let cursor_resize_horizontal: i32 = 1;
let cursor_text: i32 = 2;

struct Shadow {
    blur: f32 = 0.0, spread: f32 = 0.0, x: f32 = 0.0, y: f32 = 0.0,
    color: u32 = 0, opacity: f32 = 0.0
}
fn drop_shadow(blur: f32 = 12.0, y: f32 = 4.0, opacity: f32 = 0.25) -> Shadow {
    Shadow { blur: blur, y: y, opacity: opacity }
}

// Align: 0=start, 1=center, 2=end, 3=stretch. Justify uses 3=space-between.
struct Box {
    width: f32 = 0.0, height: f32 = 0.0, grow: f32 = 0.0,
    gap: f32 = 0.0, padding: f32 = 0.0, align: i32 = 0, justify: i32 = 0,
    fill: bool = false, center: bool = false, clip: bool = false,
    // Zero is transparent unless opaque=true (for an opaque black box).
    background: u32 = 0, opaque: bool = false, radius: f32 = 0.0,
    shadow: Shadow = Shadow {}
}
struct TextOptions { size: f32 = 0.0, bold: bool = false, color: i64 = -1, width: f32 = 0.0, align: i32 = 0 }
struct ButtonStyle {
    flat: bool = false, background: i64 = -1, hover: i64 = -1, pressed: i64 = -1,
    selected: i64 = -1, color: i64 = -1, selected_color: i64 = -1,
    radius: f32 = -1.0, align: i32 = 1
}
struct ButtonOptions {
    width: f32 = 0.0, primary: bool = false, disabled: bool = false, key: const u8[:] = "", shadow: Shadow = Shadow {},
    selected: bool = false, style: ButtonStyle = ButtonStyle {}
}
struct CheckOptions { disabled: bool = false, key: const u8[:] = "" }
struct SliderOptions { width: f32 = 200.0, step: f32 = 1.0, disabled: bool = false, key: const u8[:] = "" }
struct InputOptions { width: f32 = 240.0, placeholder: const u8[:] = "", password: bool = false, key: const u8[:] = "", flat: bool = false, id: u64 = 0 }
struct SelectOptions { width: f32 = 240.0, visible_rows: i32 = 8, disabled: bool = false, key: const u8[:] = "" }
struct ScrollState { offset: f32 = 0.0 }
struct ListRange { first: i64 = 0, end: i64 = 0 }
// Selection is independent of row order and visibility. generation distinguishes
// reused application IDs (for example a new process with the same PID).
struct ListItem { id: u64 = 0, generation: u64 = 0, disabled: bool = false }
struct ListSelection {
    item: ListItem = ListItem {}, has_selection: bool = false,
    index: i64 = -1, owner: u64 = 0, reveal: bool = false
}
// Reserve optional leaf kinds here so new core controls cannot alias them.
// These constants add no optional package storage or native dependencies.
let kind_canvas: i32 = 14;
let kind_image: i32 = 15;
let kind_chart: i32 = 16;
let kind_selectable_list: i32 = 17;
let kind_selectable_row: i32 = 18;
struct TextInput {
    bytes: u8[..4096] = [], cursor: i64 = 0, anchor: i64 = 0, submitted: bool = false,
    drag_start: i64 = 0, drag_end: i64 = 0, drag_mode: i32 = 0
}
struct TextDocument {
    bytes: u8[..65536] = [], cursor: i64 = 0, anchor: i64 = 0, scroll: f32 = 0.0,
    window_start: i64 = 0, horizontal: f32 = 0.0,
    drag_start: i64 = 0, drag_end: i64 = 0, drag_mode: i32 = 0
}
struct AreaOptions { width: f32 = 0.0, height: f32 = 300.0, size: f32 = 14.0, line_numbers: bool = true, key: const u8[:] = "" }
struct Event {
    // 0=none, 1=move, 2=press, 3=release, 4=wheel, 5=key, 6=Unicode scalar,
    // 7=blur/dismiss focus, 8=resize/DPI, 9=timer, 10=IME preedit, 11=commit, 12=cancel/end,
    // 13=lost native pointer capture (keyboard focus is retained), 14=context menu request,
    // 15=display frame, 16=scroll animation wake.
    kind: i32 = 0, x: f32 = 0.0, y: f32 = 0.0, code: i32 = 0, delta: f32 = 0.0,
    shift: bool = false, ctrl: bool = false, scroll_pixels: bool = false, scroll_smooth: bool = false
}
// Pixel input is already a distance. Detents retain each control's wheel step.
fn scroll_distance(e: Event, step: f32) -> f32 { if e.scroll_pixels { e.delta } else { e.delta * step } }
// One wheel gesture owns one control. Sampling is independent of event kind,
// so a frame triggered by a timer or mouse movement always has a fresh offset.
fn scroll_offset(c: Context&, id: u64, offset: f32, limit: f32, step: f32, hovered: bool) -> f32 {
    let maximum = max(0.0, limit);
    if c.scroll_owner == id {
        if offset != c.scroll.value as! f32 { c.scroll_owner = 0; }
        else {
            c.scroll_seen = true;
            if c.scroll.target > maximum { target_scroll(c.scroll, maximum, c.frame_ns); }
        }
    }
    if c.event.kind == 4 && hovered {
        let distance = -scroll_distance(c.event, step);
        if c.event.scroll_smooth && !c.event.scroll_pixels {
            if c.scroll_owner != id {
                c.scroll = ScrollMotion { value: offset, target: offset }; c.scroll_owner = id;
            }
            sample_scroll(c.scroll, c.frame_ns);
            let reverse = (c.scroll.target - c.scroll.value) * distance < 0.0;
            let target = clamp((if reverse { c.scroll.value } else { c.scroll.target }) + distance, 0.0, maximum) as! f32;
            if reverse { c.scroll.velocity = 0.0; c.scroll.active = false; }
            target_scroll(c.scroll, target, c.frame_ns); c.scroll_seen = true;
        } else {
            if c.scroll_owner == id { c.scroll_owner = 0; }
            return clamp(offset + distance, 0.0, maximum);
        }
    }
    if c.scroll_owner != id { return clamp(offset, 0.0, maximum); }
    let value = clamp(sample_scroll(c.scroll, c.frame_ns), 0.0, maximum);
    if !c.scroll.active { c.scroll_owner = 0; }
    value
}
struct Node {
    // 0=column, 1=row, 2=text, 3=button, 4=check, 5=toggle, 6=slider, 7=progress, 8=input, 9=divider.
    // 10=text area, 11=select, 12=popup, 13=option; kinds 14+ are named above.
    kind: i32 = 0, parent: i32 = 0, first: i32 = 0, last: i32 = 0, next: i32 = 0,
    id: u64 = 0, box: Box = Box {}, rect: Rect = Rect {}, clip_rect: Rect = Rect {},
    measured_w: f32 = 0.0, measured_h: f32 = 0.0,
    start: i32 = 0, length: i32 = 0, size: f32 = 0.0, bold: bool = false,
    color: u32 = 0, background: u32 = 0,
    disabled: bool = false, checked: bool = false, keyed: bool = false, value: f32 = 0.0,
    caret: f32 = 0.0, selection_x: f32 = 0.0, selection_w: f32 = 0.0, text_scroll: f32 = 0.0,
    composition_x: f32 = 0.0, composition_w: f32 = 0.0,
    target_x: f32 = 0.0, target_w: f32 = 0.0, ime_owner: u64 = 0, ime_x: f32 = 0.0,
    overlay: bool = false, cursor: i32 = 0, focus_target: u64 = 0
}
struct Stamp { hash: u64 = 0, rect: Rect = Rect {} }
struct WidthEntry { hash: u64 = 0, width: f32 = 0.0 }
struct Composition {
    text: u8[..4096] = [], owner: u64 = 0, active: bool = false,
    cursor: i64 = 0, target_start: i64 = 0, target_end: i64 = 0
}
let cancel_explicit: i32 = 1;
let cancel_blur: i32 = 2;
let cancel_capture_lost: i32 = 3;
let cancel_escape: i32 = 4;
let cancel_resize: i32 = 5;
let cancel_disabled: i32 = 6;
let cancel_removed: i32 = 7;
let cancel_focus: i32 = 8;
let cancel_replaced: i32 = 9;
let cancel_geometry: i32 = 10;
// One pointer owns capture and drag origin for the whole context. Individual
// controls keep their semantic values (selection anchors, widths, offsets).
struct PointerState {
    pressed: u64 = 0, released: u64 = 0, cancelled: u64 = 0, reason: i32 = 0,
    drag_owner: u64 = 0, x: f32 = 0.0, y: f32 = 0.0, value: f32 = 0.0, space: Rect = Rect {}
}
struct Interaction {
    hovered: bool = false, focused: bool = false, pressed: bool = false,
    held: bool = false, released: bool = false, activated: bool = false,
    cancelled: bool = false, reason: i32 = 0
}
struct PointerDrag {
    started: bool = false, held: bool = false, released: bool = false,
    update: bool = false, cancelled: bool = false, reason: i32 = 0,
    value: f32 = 0.0, dx: f32 = 0.0, dy: f32 = 0.0
}
struct Context {
    nodes: Node[1024] = [Node {}; 1024], count: i32 = 0, parent: i32 = -1,
    text_bytes: u8[65536] = [0; 65536], text_count: i32 = 0,
    previous: Stamp[1024] = [Stamp {}; 1024], previous_count: i32 = 0,
    widths: WidthEntry[512] = [WidthEntry {}; 512],
    theme: Theme = Theme {}, width: f32 = 640.0, height: f32 = 480.0,
    event: Event = Event {}, mouse_x: f32 = -1.0, mouse_y: f32 = -1.0,
    hot: u64 = 0, active: u64 = 0, focus: u64 = 0, clicked: u64 = 0,
    pointer: PointerState = PointerState {},
    scroll: ScrollMotion = ScrollMotion {}, scroll_owner: u64 = 0,
    scroll_seen: bool = false, frame_ns: i64 = 0,
    changed: bool = false, keyboard_focus: bool = false, dirty: Rect = Rect {}, force: bool = true,
    regions: DamageRegions = DamageRegions {}, paint_regions: i32 = 0,
    last_background: u32 = 0, frames: i64 = 0, paints: i64 = 0,
    ime: Composition = Composition {},
    popup: u64 = 0, popup_highlight: i64 = 0, popup_first: i64 = 0,
    popup_count: i64 = 0, popup_rows: i32 = 0, popup_rect: Rect = Rect {}, popup_anchor: Rect = Rect {},
    popup_menu: bool = false, popup_wheel: f32 = 0.0
}

extern fn mg_measure(text: const u8[:], size: f32, bold: bool) -> f32;
extern fn mg_clipboard_get(out: u8[:]) -> i64;
extern fn mg_clipboard_set(text: const u8[:]) -> bool;
// 0: arrow, 1: horizontal resize. Applied centrally after layout and hit testing.
extern fn mg_cursor(shape: i32);
extern fn mg_capture(enabled: bool) -> bool;
extern fn mg_scroll_animation(active: bool);

fn node_text(c: Context&, i: i32) -> u8[:] {
    let n .= c.nodes[i]; c.text_bytes[n.start..n.start + n.length]
}
fn text_width(c: Context&, s: const u8[:], size: f32, bold: bool = false) -> f32 {
    let h = mix(mix(hash_text(s), (size * 64.0) as! u64), if bold { 1 } else { 0 });
    let slot = (h % 512) as i32;
    if c.widths[slot].hash == h { return c.widths[slot].width; }
    let width = mg_measure(s, size, bold);
    c.widths[slot] = WidthEntry { h, width };
    width
}
fn button_kind(n: Node&) -> bool { n.kind == 3 || n.kind == kind_selectable_row }
fn interactive(n: Node&) -> bool {
    ((n.kind >= 3 && n.kind <= 8 && n.kind != 7) || n.kind == 10 || n.kind == 11 || n.kind == 13 ||
        n.kind == kind_selectable_list || n.kind == kind_selectable_row || (n.kind <= 1 && n.focus_target != 0)) && !n.disabled
}
fn focusable(n: Node&) -> bool { interactive(n) && n.kind > 1 && n.kind != 13 && n.kind != kind_selectable_row }
// Container padding and decorative children focus a descendant control. The
// container is a pointer target, not an extra Tab stop; child controls win hits.
fn focus_proxy(c: Context&, container: i32, target: i32) -> bool {
    assert(container >= 0 && container < c.count && c.nodes[container].kind <= 1);
    assert(target >= 0 && target < c.count);
    var parent = c.nodes[target].parent;
    while parent >= 0 && parent != container { parent = c.nodes[parent].parent; }
    assert(parent == container);
    let enabled = focusable(c.nodes[target]);
    c.nodes[container].focus_target = if enabled { c.nodes[target].id } else { 0 };
    enabled
}
fn pointer_focus(c: Context&, owner: u64) -> u64 {
    for i: i32 in c.count { if c.nodes[i].id == owner {
        var target = i;
        while target >= 0 {
            let proxy = c.nodes[target].focus_target;
            if c.nodes[target].kind <= 1 && proxy != 0 {
                for j: i32 in c.count { if c.nodes[j].id == proxy && focusable(c.nodes[j]) { return proxy; } }
                return 0;
            }
            if focusable(c.nodes[target]) { return c.nodes[target].id; }
            target = c.nodes[target].parent;
        }
        break;
    } } 0
}
fn button_focused(c: Context&, i: i32) -> bool {
    let n .= c.nodes[i];
    if n.id == c.focus { return true; }
    if n.kind == kind_selectable_row && n.checked {
        var parent = n.parent;
        while parent >= 0 {
            if c.nodes[parent].kind == kind_selectable_list { return c.nodes[parent].id == c.focus; }
            parent = c.nodes[parent].parent;
        }
    } false
}
fn cancel_pointer(c: Context&, reason: i32 = cancel_explicit) {
    let owner = if c.active != 0 { c.active } else { if c.pointer.drag_owner != 0 { c.pointer.drag_owner } else { c.pointer.released } };
    if owner != 0 {
        c.pointer.cancelled = owner; c.pointer.reason = reason; c.changed = true;
        if c.clicked == owner { c.clicked = 0; }
    }
    c.active = 0; c.pointer.drag_owner = 0; c.pointer.pressed = 0; c.pointer.released = 0;
    mg_capture(false);
}
fn capture_pointer(c: Context&, owner: u64) -> bool {
    if owner != 0 {
        var exists = false;
        for i: i32 in c.count { if c.nodes[i].id == owner && interactive(c.nodes[i]) { exists = true; break; } }
        if !exists { return false; }
    }
    if c.active != 0 && c.active != owner { cancel_pointer(c, cancel_replaced); }
    c.active = owner;
    if owner == 0 { mg_capture(false); return false; }
    if !mg_capture(true) { cancel_pointer(c, cancel_capture_lost); return false; }
    true
}
fn focus(c: Context&, owner: u64, keyboard: bool = false) -> bool {
    if owner != 0 {
        var exists = false;
        for i: i32 in c.count { if c.nodes[i].id == owner && focusable(c.nodes[i]) { exists = true; break; } }
        if !exists { return false; }
    }
    if c.focus != owner {
        if c.active != 0 && c.active != owner { cancel_pointer(c, cancel_focus); }
        c.focus = owner; cancel_composition(c); c.changed = true;
    }
    if c.keyboard_focus != keyboard { c.changed = true; }
    c.keyboard_focus = keyboard; true
}
fn interaction(c: Context&, i: i32) -> Interaction {
    let n .= c.nodes[i]; let id = n.id;
    if !interactive(n) {
        if c.active == id || c.pointer.drag_owner == id || c.pointer.released == id { cancel_pointer(c, cancel_disabled); }
        if c.focus == id { focus(c, 0, c.keyboard_focus); }
    }
    let available = interactive(n);
    Interaction {
        hovered: available && c.hot == id, focused: available && c.focus == id,
        pressed: available && c.active == id && c.pointer.pressed == id && c.event.kind == 2,
        held: available && c.active == id, released: available && c.pointer.released == id && c.event.kind == 3,
        activated: available && (c.clicked == id || (c.popup == 0 && c.focus == id && c.event.kind == 5 && (c.event.code == key_enter || c.event.code == key_space))),
        cancelled: c.pointer.cancelled == id, reason: if c.pointer.cancelled == id { c.pointer.reason } else { 0 }
    }
}
// space describes the stable coordinate domain, excluding the moving thumb
// or divider itself. A changed domain invalidates the original drag mapping.
fn pointer_drag(c: Context&, i: i32, value: f32 = 0.0, space: Rect = Rect {}) -> PointerDrag {
    let status = interaction(c, i); let id = c.nodes[i].id;
    if status.pressed {
        c.pointer.drag_owner = id; c.pointer.x = c.mouse_x; c.pointer.y = c.mouse_y;
        c.pointer.value = value; c.pointer.space = space;
    }
    if c.pointer.drag_owner == id {
        let prior = c.pointer.space;
        if prior.x != space.x || prior.y != space.y || prior.w != space.w || prior.h != space.h { cancel_pointer(c, cancel_geometry); }
    }
    let owns = c.pointer.drag_owner == id;
    let update = owns && (status.pressed || (status.held && c.event.kind == 1) || status.released);
    let result = PointerDrag { started: owns && status.pressed, held: owns && status.held, released: owns && status.released,
        update: update, cancelled: c.pointer.cancelled == id, reason: if c.pointer.cancelled == id { c.pointer.reason } else { 0 },
        value: c.pointer.value, dx: if owns { c.mouse_x - c.pointer.x } else { 0.0 }, dy: if owns { c.mouse_y - c.pointer.y } else { 0.0 } };
    if status.released && owns { c.pointer.drag_owner = 0; }
    result
}
fn finish_input(c: Context&) {
    c.clicked = 0; c.event = Event {};
    c.pointer.pressed = 0; c.pointer.released = 0; c.pointer.cancelled = 0; c.pointer.reason = 0;
}
fn reconcile_interaction(c: Context&) {
    var active: i32 = -1; var focused: i32 = -1;
    for i: i32 in c.count {
        if c.nodes[i].id == c.active { active = i; }
        if c.nodes[i].id == c.focus { focused = i; }
    }
    if c.active != 0 {
        if active < 0 { cancel_pointer(c, cancel_removed); }
        else { if !interactive(c.nodes[active]) { cancel_pointer(c, cancel_disabled); } }
    }
    if c.focus != 0 { if focused < 0 { focus(c, 0, c.keyboard_focus); } else { if !focusable(c.nodes[focused]) { focus(c, 0, c.keyboard_focus); } } }
    if c.pointer.drag_owner != 0 && c.active != c.pointer.drag_owner {
        if c.pointer.released == c.pointer.drag_owner { c.pointer.drag_owner = 0; }
        else { cancel_pointer(c, cancel_removed); }
    }
}
fn hit(c: Context&, x: f32, y: f32) -> u64 {
    var i = c.count;
    while i > 0 { i -= 1; let n .= c.nodes[i];
        if c.popup != 0 && !n.overlay && n.id != c.popup { continue; }
        if interactive(n) && contains(intersect(n.rect, n.clip_rect), x, y) { return n.id; }
    } return 0;
}
fn send(c: Context&, e: Event) {
    if e.kind == 5 && c.ime.active { c.event = Event {}; c.clicked = 0; return; }
    finish_input(c);
    c.event = e; c.clicked = 0;
    if e.kind == 2 || e.kind == 5 || e.kind == 7 || e.kind == 8 || e.kind == 14 { c.scroll_owner = 0; }
    if e.kind == 14 { c.popup = 0; cancel_pointer(c); cancel_composition(c); c.keyboard_focus = false; }
    if e.kind == 2 { c.keyboard_focus = false; }
    if e.kind == 5 { c.keyboard_focus = true; }
    if (e.kind >= 1 && e.kind <= 4) || e.kind == 14 { c.mouse_x = e.x; c.mouse_y = e.y; }
    c.hot = hit(c, c.mouse_x, c.mouse_y);
    let open_popup = c.popup;
    if e.kind == 14 { focus(c, pointer_focus(c, c.hot)); }
    if open_popup != 0 {
        if c.popup_menu && e.kind == 4 { c.event = Event {}; return; }
        if e.kind == 7 || (e.kind == 5 && (e.code == key_escape || e.code == key_tab)) {
            c.popup = 0;
            if e.kind == 5 && e.code == key_escape { cancel_pointer(c, cancel_escape); c.event = Event {}; return; }
        }
        if e.kind == 2 && !contains(c.popup_rect, e.x, e.y) && !contains(c.popup_anchor, e.x, e.y) {
            c.popup = 0; cancel_pointer(c); c.event = Event {}; cancel_composition(c); return;
        }
        if e.kind == 4 && contains(c.popup_rect, e.x, e.y) {
            c.popup_wheel += if e.scroll_pixels { e.delta / 30.0 } else { e.delta * 3.0 };
            let rows = c.popup_wheel as! i64;
            let last = max(0, c.popup_count - c.popup_rows);
            c.popup_first = clamp(c.popup_first - rows, 0, last);
            c.popup_wheel -= rows;
            if (c.popup_first == 0 && c.popup_wheel > 0.0) || (c.popup_first == last && c.popup_wheel < 0.0) { c.popup_wheel = 0.0; }
            c.popup_highlight = clamp(c.popup_highlight, c.popup_first, min(c.popup_count - 1, c.popup_first + c.popup_rows - 1));
            c.event = Event {}; return;
        }
    }
    if e.kind == 2 {
        if c.active != 0 { cancel_pointer(c, cancel_replaced); }
        focus(c, if open_popup != 0 && contains(c.popup_rect, e.x, e.y) { open_popup } else { pointer_focus(c, c.hot) });
        if capture_pointer(c, c.hot) { c.pointer.pressed = c.hot; }
    }
    if e.kind == 3 {
        c.pointer.released = c.active;
        if c.active != 0 && c.active == c.hot { c.clicked = c.hot; }
        c.active = 0; mg_capture(false);
    }
    if e.kind == 7 { cancel_pointer(c, cancel_blur); focus(c, 0); c.hot = 0; }
    if e.kind == 8 { cancel_pointer(c, cancel_resize); }
    if e.kind == 13 { cancel_pointer(c, cancel_capture_lost); }
    if e.kind == 5 && e.code == key_escape && c.active != 0 {
        cancel_pointer(c, cancel_escape); c.event = Event {};
    }
    if e.kind == 5 && e.code == key_tab {
        var found: i32 = -1; var first: u64 = 0; var last: u64 = 0; var next: u64 = 0;
        for i: i32 in c.count {
            let n .= c.nodes[i];
            if focusable(n) {
                if first == 0 { first = n.id; }
                if n.id == c.focus { found = i; if e.shift { next = last; } }
                else { if found >= 0 && !e.shift && next == 0 { next = n.id; } }
                last = n.id;
            }
        }
        if next == 0 { next = if e.shift { last } else { first }; }
        focus(c, next, true);
    }
    if e.kind == 7 || e.kind == 12 || e.kind == 2 { cancel_composition(c); }
}
fn cancel_composition(c: Context&) {
    c.ime.active = false; c.ime.text.clear(); c.ime.owner = 0;
    c.ime.cursor = 0; c.ime.target_start = 0; c.ime.target_end = 0;
}
fn utf8_boundary(s: const u8[:], position: i64) -> i64 {
    var p = clamp(position, 0, s.len);
    while p > 0 && p < s.len && (s[p] & 0xc0) == 0x80 { p -= 1; } p
}
fn composition(c: Context&, value: const u8[:], cursor: i64 = 0, target_start: i64 = 0, target_end: i64 = 0, committed: bool = false) {
    send(c, Event { kind: if committed { 11 } else { 10 } });
    c.ime.text.clear(); assert(value.len <= c.ime.text.cap); c.ime.text.append(value);
    c.ime.owner = c.focus; c.ime.active = !committed && c.focus != 0;
    c.ime.cursor = utf8_boundary(value, cursor); c.ime.target_start = utf8_boundary(value, target_start);
    c.ime.target_end = max(c.ime.target_start, utf8_boundary(value, target_end));
}
fn begin(c: Context&, width: f32, height: f32) {
    if c.width != width || c.height != height { c.force = true; cancel_pointer(c, cancel_resize); c.scroll_owner = 0; }
    c.width = width; c.height = height; c.count = 0; c.text_count = 0; c.parent = -1; c.changed = false;
    c.frame_ns = mg_frame_time_ns(); c.scroll_seen = false;
    let root = add(c, 0, "", "root");
    c.nodes[root].box = Box { width: width, height: height, align: 3 };
    c.parent = root;
}
fn add(c: Context&, kind: i32, label: const u8[:], key: const u8[:] = "") -> i32 {
    assert(c.count < max_nodes);
    assert(label.len <= max_text - c.text_count);
    let i = c.count; c.count += 1;
    let seed = if c.parent >= 0 { c.nodes[c.parent].id } else { 14695981039346656037 };
    let id = if key.len > 0 { hash_text(key, seed) } else { mix(hash_text(label, seed), i as u64) };
    c.nodes[i] = Node { kind: kind, parent: c.parent, first: -1, last: -1, next: -1, id: id, start: c.text_count, length: label.len as i32,
        size: c.theme.font_size, color: c.theme.text, background: c.theme.surface, keyed: key.len > 0, caret: -1.0 };
    for b in label { c.text_bytes[c.text_count] = b; c.text_count += 1; }
    if c.parent >= 0 {
        let p .= c.nodes[c.parent];
        if p.last >= 0 { c.nodes[p.last].next = i; } else { p.first = i; }
        p.last = i;
    }
    i
}
// Optional renderers copy their payload into the same bounded frame arena.
fn add_leaf(c: Context&, kind: i32, data: const u8[:], width: f32, height: f32, key: const u8[:] = "") -> i32 {
    assert(kind >= kind_canvas && width > 0.0 && height > 0.0);
    let i = add(c, kind, data, key); c.nodes[i].box = Box { width: width, height: height }; i
}
fn row(c: Context&, box: Box = Box {}, key: const u8[:] = "") { let i = add(c, 1, "", key); c.nodes[i].box = box; c.parent = i; }
fn column(c: Context&, box: Box = Box {}, key: const u8[:] = "") { let i = add(c, 0, "", key); c.nodes[i].box = box; c.parent = i; }
fn end(c: Context&) { assert(c.parent > 0); c.parent = c.nodes[c.parent].parent; }
// Trailing blocks are compile-time callbacks. Like any Goose HOF, closing
// runs on normal completion only: non-local return bypasses the closing code.
fn row<Children>(c: Context&, box: Box = Box {}, key: const u8[:] = "") {
    row(c, box, key); Children(); end(c);
}
fn column<Children>(c: Context&, box: Box = Box {}, key: const u8[:] = "") {
    column(c, box, key); Children(); end(c);
}
fn text(c: Context&, s: const u8[:], options: TextOptions = TextOptions {}) {
    let i = add(c, 2, s); let n .= c.nodes[i]; n.size = if options.size > 0.0 { options.size } else { c.theme.font_size };
    n.bold = options.bold; n.box.width = options.width;
    n.box.align = options.align;
    if options.color >= 0 { n.color = options.color as u32; }
}
fn text_number(c: Context&, value: i64, options: TextOptions = TextOptions {}) {
    var s: u8[>..] = []; format(s, value); text(c, s, options);
}
fn activated(c: Context&, i: i32) -> bool {
    let yes = interaction(c, i).activated;
    if yes { c.changed = true; } yes
}
fn button_parent_background(c: Context&, parent: i32) -> u32 {
    var p = parent;
    while p >= 0 {
        let n .= c.nodes[p];
        if n.box.opaque || n.box.background != 0 { return n.box.background; }
        p = n.parent;
    }
    c.theme.background
}
fn button_node(c: Context&, label: const u8[:], options: ButtonOptions = ButtonOptions {}) -> i32 {
    let i = add(c, 3, label, options.key); let n .= c.nodes[i]; let s = options.style;
    n.box.width = options.width; n.box.height = 34.0; n.box.radius = if s.radius >= 0.0 { s.radius } else { c.theme.radius };
    n.box.shadow = options.shadow; n.disabled = options.disabled; n.checked = options.selected;
    let custom = s.flat || s.background >= 0 || s.hover >= 0 || s.pressed >= 0 || s.selected >= 0 ||
        s.color >= 0 || s.selected_color >= 0 || s.radius >= 0.0 || s.align != 1 || options.selected;
    // Buttons reuse value for appearance flags: 0=default, 1=custom, 2=flat.
    n.value = if s.flat { 2.0 } else { if custom { 1.0 } else { 0.0 } };
    n.box.align = s.align;
    if options.primary { n.background = c.theme.accent; n.color = c.theme.accent_text; }
    if custom {
        if s.flat && !options.primary { n.background = button_parent_background(c, n.parent); }
        if s.background >= 0 { n.background = s.background as u32; }
        if s.color >= 0 { n.color = s.color as u32; }
        if options.selected {
            n.background = if s.selected >= 0 { s.selected as u32 } else { c.theme.accent };
            n.color = if s.selected_color >= 0 { s.selected_color as u32 } else { c.theme.accent_text };
        }
        if !n.disabled {
            if c.hot == n.id { n.background = if s.hover >= 0 { s.hover as u32 } else { c.theme.hover }; }
            if c.active == n.id { n.background = if s.pressed >= 0 { s.pressed as u32 } else { c.theme.pressed }; }
        }
    }
    i
}
fn button(c: Context&, label: const u8[:], options: ButtonOptions = ButtonOptions {}) -> bool {
    activated(c, button_node(c, label, options))
}
// Content participates in normal measurement and inherits one focus/click
// target. The callback receives its button index for app-owned focus metadata.
fn button_content<Children>(c: Context&, box: Box, options: ButtonOptions = ButtonOptions {}) -> bool {
    let i = button_node(c, "", options); let original = c.nodes[i].box;
    c.nodes[i].box = box;
    if box.width == 0.0 { c.nodes[i].box.width = original.width; }
    if box.radius == 0.0 { c.nodes[i].box.radius = original.radius; }
    if box.shadow.opacity == 0.0 { c.nodes[i].box.shadow = original.shadow; }
    c.parent = i; Children(i); end(c); activated(c, i)
}
fn checkbox(c: Context&, label: const u8[:], value: bool&, options: CheckOptions = CheckOptions {}) -> bool {
    let i = add(c, 4, label, options.key); c.nodes[i].disabled = options.disabled;
    let yes = activated(c, i); if yes { value = !value; } c.nodes[i].checked = value; yes
}
fn toggle(c: Context&, label: const u8[:], value: bool&, options: CheckOptions = CheckOptions {}) -> bool {
    let i = add(c, 5, label, options.key); c.nodes[i].disabled = options.disabled;
    let yes = activated(c, i); if yes { value = !value; } c.nodes[i].checked = value; yes
}
fn radio(c: Context&, label: const u8[:], selected: bool, options: CheckOptions = CheckOptions {}) -> bool {
    var value = selected; checkbox(c, label, value, options)
}
fn prior_rect(c: Context&, id: u64) -> Rect {
    // Previous scene stamps keep the same order as the last build.
    for i: i32 in c.previous_count { if c.previous[i].hash == id { return c.previous[i].rect; } }
    Rect {}
}
fn slider(c: Context&, value: f32&, lo: f32, hi: f32, options: SliderOptions = SliderOptions {}) -> bool {
    assert(hi > lo); assert(options.step > 0.0);
    let i = add(c, 6, "", options.key); let n .= c.nodes[i];
    n.box.width = options.width; n.box.height = 28.0; n.disabled = options.disabled;
    let old = value;
    let drag = pointer_drag(c, i, 0.0, Rect { w: options.width, h: 28.0 });
    if drag.update {
        let r = prior_rect(c, n.id);
        if r.w > 12.0 { value = lo + clamp((c.mouse_x - r.x - 6.0) / (r.w - 12.0), 0.0, 1.0) * (hi - lo); }
    }
    if !options.disabled && c.focus == n.id && c.event.kind == 5 {
        if c.event.code == key_left || c.event.code == key_down { value -= options.step; }
        if c.event.code == key_right || c.event.code == key_up { value += options.step; }
        if c.event.code == key_home { value = lo; } if c.event.code == key_end { value = hi; }
    }
    value = clamp(lo + (((value - lo) / options.step + 0.5) as! i64) * options.step, lo, hi);
    n.value = (value - lo) / (hi - lo);
    if value != old { c.changed = true; } value != old
}
fn progress(c: Context&, value: f32, width: f32 = 200.0) {
    let i = add(c, 7, ""); c.nodes[i].value = clamp(value, 0.0, 1.0);
    c.nodes[i].box = Box { width: width, height: 8.0 };
}
fn divider(c: Context&) { let i = add(c, 9, ""); c.nodes[i].box = Box { height: 1.0 }; }
fn spacer(c: Context&, grow: f32 = 1.0) { let i = add(c, 0, ""); c.nodes[i].box.grow = grow; }

fn prev_char<T>(t: T&, at: i64) -> i64 {
    var p = max(0, at - 1); while p > 0 && (t.bytes[p] & 0xc0) == 0x80 { p -= 1; } p
}
fn next_char<T>(t: T&, at: i64) -> i64 {
    var p = min(t.bytes.len, at + 1); while p < t.bytes.len && (t.bytes[p] & 0xc0) == 0x80 { p += 1; } p
}
fn character_count(value: const u8[:]) -> i64 {
    var count = 0; for ch in value { if (ch & 0xc0) != 0x80 { count += 1; } } count
}
fn erase_selection<T>(t: T&) -> bool {
    let lo = min(t.cursor, t.anchor); let hi = max(t.cursor, t.anchor);
    if lo == hi { return false; }
    let remain = t.bytes.len - hi;
    for j in remain { t.bytes[lo + j] = t.bytes[hi + j]; }
    t.bytes.resize(t.bytes.len - (hi - lo)); t.cursor = lo; t.anchor = lo; true
}
fn insert_text<T>(t: T&, value: const u8[:]) -> bool {
    // All or nothing on overflow; do not delete a selection on failed insertion.
    let removed = abs(t.cursor - t.anchor);
    if value.len > t.bytes.cap - t.bytes.len + removed { return false; }
    erase_selection(t);
    let old = t.bytes.len; t.bytes.resize(old + value.len, 0);
    var j = old;
    while j > t.cursor { j -= 1; t.bytes[j + value.len] = t.bytes[j]; }
    for k in value.len { t.bytes[t.cursor + k] = value[k]; }
    t.cursor += value.len; t.anchor = t.cursor; true
}
fn insert_scalar<T>(t: T&, cp: i32) -> bool {
    if cp < 32 || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) { return false; }
    var s: u8[..4] = [];
    if cp < 0x80 { s.push(cp as u8); }
    else { if cp < 0x800 { s.push((0xc0 | (cp >> 6)) as! u8); }
        else { if cp < 0x10000 { s.push((0xe0 | (cp >> 12)) as! u8); }
            else { s.push((0xf0 | (cp >> 18)) as! u8); s.push((0x80 | ((cp >> 12) & 63)) as! u8); }
            s.push((0x80 | ((cp >> 6) & 63)) as! u8); }
        s.push((0x80 | (cp & 63)) as! u8); }
    insert_text(t, s)
}
fn character_class<T>(t: T&, at: i64) -> i32 {
    if at >= t.bytes.len { return 0; }
    let ch = t.bytes[at];
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' { return 0; }
    if ch >= 128 || ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') { return 1; }
    2
}
fn word_start<T>(t: T&, at: i64) -> i64 {
    var p = at; if p == t.bytes.len && p > 0 { p = prev_char(t, p); }
    let kind = character_class(t, p);
    while p > 0 && character_class(t, prev_char(t, p)) == kind { p = prev_char(t, p); } p
}
fn word_end<T>(t: T&, at: i64) -> i64 {
    var p = at; if p == t.bytes.len && p > 0 { p = prev_char(t, p); }
    let kind = character_class(t, p);
    while p < t.bytes.len && character_class(t, p) == kind { p = next_char(t, p); } p
}
fn previous_word<T>(t: T&, at: i64) -> i64 {
    var p = at;
    while p > 0 && character_class(t, prev_char(t, p)) == 0 { p = prev_char(t, p); }
    if p > 0 { p = word_start(t, prev_char(t, p)); } p
}
fn next_word<T>(t: T&, at: i64) -> i64 {
    var p = at;
    if p < t.bytes.len { p = word_end(t, p); }
    while p < t.bytes.len && character_class(t, p) == 0 { p = next_char(t, p); } p
}
fn selection_pointer<T>(t: T&, at: i64, event: Event, multiline: bool) {
    let p = utf8_boundary(t.bytes, at);
    if event.kind == 2 {
        t.drag_mode = 0;
        if event.code >= 2 {
            t.drag_start = word_start(t, p); t.drag_end = word_end(t, p); t.drag_mode = 1;
            if event.code >= 3 {
                t.drag_start = if multiline { start_of_line(t.bytes, p) } else { 0 };
                t.drag_end = if multiline { min(t.bytes.len, end_of_line(t.bytes, p) + 1) } else { t.bytes.len };
                t.drag_mode = 2;
            }
            t.anchor = t.drag_start; t.cursor = t.drag_end;
        } else { t.cursor = p; if !event.shift { t.anchor = p; } }
    } else {
        if t.drag_mode == 0 { t.cursor = p; }
        else { if p < t.drag_start {
            t.anchor = t.drag_end; t.cursor = if t.drag_mode == 1 { word_start(t, p) } else { if multiline { start_of_line(t.bytes, p) } else { 0 } };
        } else { if p > t.drag_end {
            t.anchor = t.drag_start; t.cursor = if t.drag_mode == 1 { word_end(t, p) } else { if multiline { min(t.bytes.len, end_of_line(t.bytes, p) + 1) } else { t.bytes.len } };
        } else { t.anchor = t.drag_start; t.cursor = t.drag_end; } } }
    }
}
fn pick_text(c: Context&, value: const u8[:], start: i64, stop: i64, x: f32, size: f32, password: bool = false) -> i64 {
    var p = start; var last: f32 = 0.0; var chars = 0;
    while p < stop {
        var next = p + 1; while next < stop && (value[next] & 0xc0) == 0x80 { next += 1; }
        chars += 1;
        let width = if password { text_width(c, "*", size) * chars } else { text_width(c, value[start..next], size) };
        if x < (last + width) * 0.5 { return p; }
        last = width; p = next;
    } p
}
fn edit_keys<T>(t: T&, e: Event, multiline: bool = false, password: bool = false) -> bool {
    let copy = e.ctrl && (e.code == 67 || e.code == 45);
    let cut = (e.ctrl && e.code == 88) || (e.shift && e.code == key_delete && !e.ctrl);
    let paste = (e.ctrl && e.code == 86) || (e.shift && e.code == 45 && !e.ctrl);
    if copy || cut {
        if !password && t.cursor != t.anchor {
            if mg_clipboard_set(t.bytes[min(t.cursor, t.anchor)..max(t.cursor, t.anchor)]) && cut { return erase_selection(t); }
        } return false;
    }
    if paste {
        var bytes: u8[>..] = []; bytes.resize(t.bytes.cap, 0);
        let len = mg_clipboard_get(bytes); if len <= 0 { return false; }
        var clean: u8[>..] = []; var p = 0;
        while p < len {
            let ch = bytes[p];
            if ch == '\r' || ch == '\n' {
                clean.push(if multiline { '\n' } else { ' ' });
                if ch == '\r' && p + 1 < len && bytes[p + 1] == '\n' { p += 1; }
            } else { if ch == '\t' { clean.push(if multiline { '\t' } else { ' ' }); }
                else { if ch >= 32 { clean.push(ch); } } }
            p += 1;
        }
        if clean.len == 0 { return false; } return insert_text(t, clean);
    }
    match e.code {
        65 => { if e.ctrl { t.anchor = 0; t.cursor = t.bytes.len; } },
        key_left, key_right => {
            if !e.shift && !e.ctrl && t.cursor != t.anchor {
                t.cursor = if e.code == key_left { min(t.cursor, t.anchor) } else { max(t.cursor, t.anchor) };
            } else {
                t.cursor = if e.code == key_left {
                    if e.ctrl { previous_word(t, t.cursor) } else { prev_char(t, t.cursor) }
                } else {
                    if e.ctrl { next_word(t, t.cursor) } else { next_char(t, t.cursor) }
                };
            }
            if !e.shift { t.anchor = t.cursor; }
        },
        key_backspace, key_delete => {
            if t.cursor == t.anchor {
                t.anchor = if e.code == key_backspace {
                    if e.ctrl { previous_word(t, t.cursor) } else { prev_char(t, t.cursor) }
                } else {
                    if e.ctrl { next_word(t, t.cursor) } else { next_char(t, t.cursor) }
                };
            }
            return erase_selection(t);
        },
        _ => {},
    }
    false
}
fn text_input(c: Context&, t: TextInput&, options: InputOptions = InputOptions {}) -> bool {
    let i = add(c, 8, "", options.key); let n .= c.nodes[i];
    if options.id != 0 { n.id = options.id; }
    n.cursor = cursor_text;
    n.value = if options.flat { 2.0 } else { 0.0 };
    n.box = Box { width: options.width, height: 34.0, radius: c.theme.radius };
    t.cursor = clamp(t.cursor, 0, t.bytes.len); t.anchor = clamp(t.anchor, 0, t.bytes.len); t.submitted = false;
    var changed = false;
    if c.focus == n.id {
        let e = c.event;
        if e.kind == 6 { changed = insert_scalar(t, e.code); }
        if e.kind == 11 && c.ime.owner == n.id { changed = insert_text(t, c.ime.text); }
        if pointer_drag(c, i, 0.0, Rect { w: options.width, h: 34.0 }).update {
            let r = prior_rect(c, n.id);
            var current: f32 = 0.0;
            if options.password { var p = 0; while p < t.cursor { current += text_width(c, "*", n.size); p = next_char(t, p); } }
            else { current = text_width(c, t.bytes[..t.cursor], n.size); }
            let target = c.mouse_x - r.x - 8.0 + max(0.0, current - options.width + 22.0);
            let at = pick_text(c, t.bytes, 0, t.bytes.len, target, n.size, options.password);
            selection_pointer(t, at, e, false);
            if options.password && e.kind == 2 && e.code >= 2 {
                t.anchor = 0; t.cursor = t.bytes.len; t.drag_start = 0; t.drag_end = t.bytes.len; t.drag_mode = 2;
            }
        }
        if e.kind == 5 {
            changed = edit_keys(t, e, false, options.password);
            match e.code {
                key_home => { t.cursor = 0; },
                key_end => { t.cursor = t.bytes.len; },
                key_enter => { t.submitted = true; },
                _ => {},
            }
            if e.code == key_left || e.code == key_right || e.code == key_home || e.code == key_end {
                if !e.shift { t.anchor = t.cursor; }
            }
        }
    }
    let composing = c.ime.active && c.ime.owner == n.id;
    var display: u8[>..] = [];
    let lo = min(t.cursor, t.anchor); let hi = max(t.cursor, t.anchor);
    var prefix: f32 = 0.0;
    if composing {
        if options.password {
            var p = 0; while p < lo { display.push('*'); p = next_char(t, p); }
        } else { display.append(t.bytes[..lo]); }
        prefix = text_width(c, display, n.size); display.append(c.ime.text);
        if options.password {
            var p = hi; while p < t.bytes.len { display.push('*'); p = next_char(t, p); }
        } else { display.append(t.bytes[hi..]); }
    } else { if options.password {
        var p = 0; while p < t.bytes.len { display.push('*'); p = next_char(t, p); }
    } else { display.append(t.bytes); } }
    if t.bytes.len == 0 && !composing { display.append(options.placeholder); n.color = c.theme.muted; }
    assert(display.len <= max_text - c.text_count);
    n.start = c.text_count; n.length = display.len as i32;
    for b in display { c.text_bytes[c.text_count] = b; c.text_count += 1; }
    if c.focus == n.id {
        if composing {
            n.caret = prefix + text_width(c, c.ime.text[..c.ime.cursor], n.size);
            n.composition_x = prefix; n.composition_w = text_width(c, c.ime.text, n.size);
            n.target_x = prefix + text_width(c, c.ime.text[..c.ime.target_start], n.size);
            n.target_w = text_width(c, c.ime.text[c.ime.target_start..c.ime.target_end], n.size);
        } else { if options.password {
            let star = text_width(c, "*", n.size);
            n.caret = star * character_count(t.bytes[..t.cursor]);
            n.selection_x = star * character_count(t.bytes[..min(t.cursor, t.anchor)]);
            n.selection_w = star * character_count(t.bytes[min(t.cursor, t.anchor)..max(t.cursor, t.anchor)]);
        } else {
            n.caret = text_width(c, t.bytes[..t.cursor], n.size);
            n.selection_x = text_width(c, t.bytes[..min(t.cursor, t.anchor)], n.size);
            n.selection_w = text_width(c, t.bytes[min(t.cursor, t.anchor)..max(t.cursor, t.anchor)], n.size);
        } }
        n.text_scroll = max(0.0, n.caret - options.width + 22.0);
        n.ime_owner = n.id; n.ime_x = if composing && n.target_w > 0.0 { n.target_x } else { n.caret };
    }
    if changed { c.changed = true; } changed
}

// A virtual list materializes only the visible rows plus one overscan row.
// Use a fixed viewport height and a stable explicit key.
fn begin_list(c: Context&, state: ScrollState&, total: i64, row_height: f32, box: Box, key: const u8[:]) -> ListRange {
    assert(total >= 0 && row_height > 0.0 && box.height > 0.0);
    column(c, box, key); let n .= c.nodes[c.parent]; n.box.clip = true; n.box.padding = 0.0; n.box.gap = 0.0;
    let r = prior_rect(c, n.id);
    state.offset = scroll_offset(c, n.id, state.offset, total * row_height - box.height, row_height * 3.0, contains(r, c.mouse_x, c.mouse_y));
    let first = (state.offset / row_height) as! i64;
    let end_index = min(total, first + (box.height / row_height) as! i64 + 2);
    // A negative top spacer places the fractional row at its true position.
    n.value = -(state.offset - first * row_height);
    ListRange { first, end_index }
}
fn virtual_list<Item>(c: Context&, state: ScrollState&, total: i64, row_height: f32, box: Box, key: const u8[:]) {
    let range = begin_list(c, state, total, row_height, box, key);
    for index in range.first..range.end { Item(index); }
    end(c);
}

fn same_item(a: ListItem, b: ListItem) -> bool { a.id == b.id && a.generation == b.generation }
fn select_item(selection: ListSelection&, item: ListItem) -> bool {
    if item.disabled { return false; }
    let changed = !selection.has_selection || !same_item(selection.item, item);
    selection.item = item; selection.has_selection = true;
    if changed { selection.reveal = true; }
    changed
}
fn clear_selection(selection: ListSelection&) -> bool {
    let changed = selection.has_selection;
    selection.has_selection = false; selection.index = -1; selection.reveal = false; changed
}
fn reveal_list_row(scroll: ScrollState&, index: i64, total: i64, row_height: f32, height: f32) {
    if index < 0 || index >= total { return; }
    let top = index * row_height; let bottom = top + row_height;
    if top < scroll.offset { scroll.offset = top; }
    else { if bottom > scroll.offset + height { scroll.offset = bottom - height; } }
    scroll.offset = clamp(scroll.offset, 0.0, max(0.0, total * row_height - height));
}
// Lookup(index) returns a ListItem directly from application data. No row-sized
// allocation is needed. Hidden/removed identities stay selected until cleared.
fn selectable_list<Lookup, Row>(c: Context&, selection: ListSelection&, scroll: ScrollState&,
                               total: i64, row_height: f32, box: Box, key: const u8[:]) -> bool {
    assert(total >= 0 && row_height > 0.0 && box.height > 0.0);
    let old_item = selection.item; let old_selected = selection.has_selection;
    let old_index = selection.index;
    selection.index = -1;
    if selection.has_selection {
        if old_index >= 0 && old_index < total && same_item(Lookup(old_index), selection.item) { selection.index = old_index; }
        else { for index in total { if same_item(Lookup(index), selection.item) { selection.index = index; break; } } }
    }
    let range = begin_list(c, scroll, total, row_height, box, key);
    let list = c.parent; c.nodes[list].kind = kind_selectable_list; selection.owner = c.nodes[list].id;
    let focused = c.focus == selection.owner;
    if selection.index != old_index && selection.index >= 0 && focused { selection.reveal = true; }
    let e = c.event;
    if focused && e.kind == 5 && (e.code == key_tab || e.code == key_enter || e.code == key_space) { selection.reveal = true; }
    if focused && e.kind == 5 && c.popup == 0 && c.active == 0 {
        if e.code == key_escape { if clear_selection(selection) { c.changed = true; } }
        let backwards = e.code == key_up || e.code == key_page_up || e.code == key_end;
        let navigation = backwards || e.code == key_down || e.code == key_page_down || e.code == key_home;
        if navigation && total > 0 {
            let page = max(1, (box.height / row_height) as! i64);
            var next = if selection.index < 0 { if e.code == key_up { total - 1 } else { 0 } } else { selection.index };
            if selection.index >= 0 {
                match e.code {
                    key_up => { next -= 1; },
                    key_down => { next += 1; },
                    key_page_up => { next -= page; },
                    key_page_down => { next += page; },
                    _ => {},
                }
            }
            if e.code == key_home { next = 0; }
            if e.code == key_end { next = total - 1; }
            next = clamp(next, 0, total - 1);
            // Home/PageDown move forward past disabled rows; End/PageUp move back.
            let direction: i64 = if backwards { -1 } else { 1 };
            while next >= 0 && next < total && Lookup(next).disabled { next += direction; }
            if next >= 0 && next < total {
                select_item(selection, Lookup(next)); selection.index = next; selection.reveal = true;
            }
        }
    }
    if selection.reveal && selection.index >= 0 {
        reveal_list_row(scroll, selection.index, total, row_height, box.height); selection.reveal = false;
    }
    // Navigation can bring any row into view, including one never materialized.
    let first = (scroll.offset / row_height) as! i64;
    c.nodes[list].value = -(scroll.offset - first * row_height);
    let stop = min(total, first + (box.height / row_height) as! i64 + 2);
    for index in first..stop { Row(index, Lookup(index)); }
    end(c);
    let changed = old_selected != selection.has_selection || (selection.has_selection && !same_item(old_item, selection.item));
    if changed || first != range.first { c.changed = true; }
    changed
}
fn selectable_row<Children>(c: Context&, selection: ListSelection&, index: i64, item: ListItem,
                           box: Box, style: ButtonStyle = ButtonStyle { flat: true, align: 0 }) -> bool {
    var row_options = ButtonOptions { selected: selection.has_selection && same_item(selection.item, item),
        disabled: item.disabled, style: style };
    // Identity, not virtual position or caller text, determines the row ID.
    var key: u8[..48] = []; format(key, item.id); key.push('/'); format(key, item.generation);
    row_options.key = key;
    let pointer_clicked = button_content(c, box, row_options) { i =>
        c.nodes[i].kind = kind_selectable_row;
        Children(i);
    };
    let clicked = pointer_clicked || (!row_options.disabled && row_options.selected && c.focus == selection.owner &&
        c.event.kind == 5 && (c.event.code == key_enter || c.event.code == key_space));
    if clicked { select_item(selection, item); selection.index = index; c.changed = true; }
    clicked
}

fn line_start(t: TextDocument&, at: i64) -> i64 {
    start_of_line(t.bytes, at)
}
fn line_end(t: TextDocument&, at: i64) -> i64 {
    var p = at; while p < t.bytes.len && t.bytes[p] != '\n' { p += 1; } p
}
fn end_of_line(s: const u8[:], at: i64) -> i64 {
    var p = at; while p < s.len && s[p] != '\n' { p += 1; } p
}
fn start_of_line(s: const u8[:], at: i64) -> i64 {
    var p = at; while p > 0 && s[p - 1] != '\n' { p -= 1; } p
}
fn text_area(c: Context&, t: TextDocument&, options: AreaOptions = AreaOptions {}) -> bool {
    assert(options.height >= 32.0 && options.size > 0.0);
    let i = add(c, 10, "", options.key); let n .= c.nodes[i];
    n.cursor = cursor_text;
    n.box = Box { width: options.width, height: options.height, padding: 8.0, align: 3, clip: true, background: c.theme.surface };
    let height = options.size * 1.5; let gutter: f32 = if options.line_numbers { 52.0 } else { 0.0 };
    let r = prior_rect(c, n.id); let e = c.event;
    var changed = false; var follow = false;
    t.cursor = clamp(t.cursor, 0, t.bytes.len); t.anchor = clamp(t.anchor, 0, t.bytes.len);
    if c.focus == n.id {
        if e.kind == 6 { changed = insert_scalar(t, e.code); follow = true; }
        if e.kind == 11 && c.ime.owner == n.id { changed = insert_text(t, c.ime.text); follow = true; }
        if pointer_drag(c, i, 0.0, Rect { w: options.width, h: options.height }).update {
            if e.kind == 1 {
                if c.mouse_y < r.y + 8.0 { t.scroll = max(0.0, t.scroll - height); }
                if c.mouse_y > r.y + r.h - 8.0 { t.scroll += height; }
            }
            let row = max(0, ((c.mouse_y - r.y - 8.0 + t.scroll) / height) as! i64);
            var p = 0; var line = 0;
            while p < t.bytes.len && line < row { if t.bytes[p] == '\n' { line += 1; } p += 1; }
            let start = p;
            let old_line = line_start(t, t.cursor);
            let target = max(0.0, c.mouse_x - r.x - 8.0 - gutter + (if old_line == start { t.horizontal } else { 0.0 }));
            if old_line == start { p = clamp(t.window_start, start, line_end(t, start)); }
            let shown = p;
            p = pick_text(c, t.bytes, shown, line_end(t, shown), target, options.size);
            selection_pointer(t, p, e, true); follow = true;
        }
        if e.kind == 5 {
            follow = true;
            changed = edit_keys(t, e, true);
            match e.code {
                key_enter => { changed = insert_text(t, "\n"); },
                key_home => { t.cursor = if e.ctrl { 0 } else { line_start(t, t.cursor) }; },
                key_end => { t.cursor = if e.ctrl { t.bytes.len } else { line_end(t, t.cursor) }; },
                key_up, key_down => {
                    let start = line_start(t, t.cursor); var column = 0; var p = start;
                    while p < t.cursor { p = next_char(t, p); column += 1; }
                    var dest = start;
                    if e.code == key_up && start > 0 { dest = line_start(t, start - 1); }
                    if e.code == key_down { dest = min(t.bytes.len, line_end(t, t.cursor) + 1); }
                    for k in column { if dest < t.bytes.len && t.bytes[dest] != '\n' { dest = next_char(t, dest); } }
                    t.cursor = dest;
                },
                _ => {},
            }
            if e.code == key_left || e.code == key_right || e.code == key_up || e.code == key_down || e.code == key_home || e.code == key_end {
                if !e.shift { t.anchor = t.cursor; }
            }
        }
    }
    let composing = c.ime.active && c.ime.owner == n.id;
    let insert_at = min(t.cursor, t.anchor);
    var preview: u8[>..] = [];
    if composing { preview.append(t.bytes[..insert_at]); preview.append(c.ime.text); preview.append(t.bytes[max(t.cursor, t.anchor)..]); follow = true; }
    let content = if composing { preview[..] } else { t.bytes[..] };
    let display_cursor = if composing { insert_at + c.ime.cursor } else { t.cursor };
    var lines = 1; var caret_line = 0;
    for b, pos in content { if b == '\n' { lines += 1; if pos < display_cursor { caret_line += 1; } } }
    let viewport = options.height - 16.0;
    if follow {
        if caret_line * height < t.scroll { t.scroll = caret_line * height; }
        if (caret_line + 1) * height > t.scroll + viewport { t.scroll = (caret_line + 1) * height - viewport; }
    }
    t.scroll = scroll_offset(c, n.id, t.scroll, lines * height - viewport, height * 3.0, contains(r, c.mouse_x, c.mouse_y));
    let first = (t.scroll / height) as! i64; let last = first + (viewport / height) as! i64 + 2;
    n.value = -(t.scroll - first * height); c.parent = i;
    var start = 0; var line = 0;
    while line < last && start <= content.len {
        let stop = end_of_line(content, start);
        if line >= first {
            row(c, Box { height: height, gap: 0.0 });
            if options.line_numbers { text_number(c, line + 1, TextOptions { size: options.size, color: c.theme.muted, width: gutter }); }
            // Bound display work even for a document consisting of one very
            // long line; the stored document remains complete.
            var shown_start = start;
            if c.focus == n.id && caret_line == line && display_cursor - start > 256 { shown_start = display_cursor - 256; }
            // Keep the whole preedit in the text window when practical.
            if composing && insert_at >= start && insert_at <= stop { shown_start = min(shown_start, insert_at); }
            while shown_start < stop && (content[shown_start] & 0xc0) == 0x80 { shown_start += 1; }
            var shown_end = min(stop, shown_start + 512);
            if composing && insert_at >= start && insert_at <= stop { shown_end = min(stop, max(shown_end, insert_at + c.ime.text.len)); }
            while shown_end > shown_start && shown_end < stop && (content[shown_end] & 0xc0) == 0x80 { shown_end -= 1; }
            let label = add(c, 2, content[shown_start..shown_end]); let ln .= c.nodes[label]; ln.size = options.size;
            ln.box.height = height; ln.box.grow = 1.0;
            if c.focus == n.id {
                if caret_line == line {
                    ln.caret = text_width(c, content[shown_start..display_cursor], options.size);
                    ln.text_scroll = max(0.0, ln.caret - max(40.0, r.w - gutter - 32.0));
                    t.window_start = shown_start; t.horizontal = ln.text_scroll;
                    ln.ime_owner = n.id; ln.ime_x = ln.caret;
                    if composing && insert_at >= shown_start && insert_at <= shown_end {
                        ln.composition_x = text_width(c, content[shown_start..insert_at], options.size);
                        ln.composition_w = text_width(c, c.ime.text, options.size);
                        ln.target_x = ln.composition_x + text_width(c, c.ime.text[..c.ime.target_start], options.size);
                        ln.target_w = text_width(c, c.ime.text[c.ime.target_start..c.ime.target_end], options.size);
                        if ln.target_w > 0.0 { ln.ime_x = ln.target_x; }
                    }
                }
                let lo = max(shown_start, min(t.cursor, t.anchor)); let hi = min(shown_end, max(t.cursor, t.anchor));
                if !composing && hi > lo { ln.selection_x = text_width(c, content[shown_start..lo], options.size); ln.selection_w = text_width(c, content[lo..hi], options.size); }
            }
            end(c);
        }
        if stop == content.len { break; } start = stop + 1; line += 1;
    }
    end(c); if changed { c.changed = true; } changed
}
