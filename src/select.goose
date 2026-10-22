namespace mygoose;
import std;
import .ui;
import .geom;

struct MenuItem { label: const u8[:] = "", shortcut: const u8[:] = "", disabled: bool = false, separator: bool = false }
fn open_context_menu(c: Context&, owner: u64, x: f32, y: f32) {
    if !focus(c, owner, c.keyboard_focus) { return; }
    cancel_pointer(c); cancel_composition(c);
    c.popup = owner; c.popup_menu = true; c.popup_anchor = Rect { x: x, y: y };
    c.popup_highlight = -1; c.popup_first = 0; c.changed = true;
}
// One bounded overlay, using shared popup options and ordinary layout children.
// Returns the activated item index; separators/disabled items cannot activate.
fn context_menu(c: Context&, owner: u64, items: const MenuItem[:], width: f32 = 260.0) -> i32 {
    if c.popup == 0 || c.popup != owner || !c.popup_menu { return -1; }
    assert(items.len > 0 && items.len <= 16 && width >= 120.0);
    let e = c.event; c.popup_count = items.len; c.popup_rows = items.len as i32;
    if c.popup_highlight >= items.len { c.popup_highlight = -1; }
    if c.popup_highlight >= 0 && (items[c.popup_highlight].disabled || items[c.popup_highlight].separator) { c.popup_highlight = -1; }
    if e.kind == 1 {
        c.popup_highlight = -1;
        for i in items.len { if !items[i].disabled && !items[i].separator && c.hot == popup_item_id(owner, i) { c.popup_highlight = i; } }
    }
    if e.kind == 5 && (e.code == key_down || e.code == key_up || e.code == key_home || e.code == key_end) {
        let direction = if e.code == key_up || e.code == key_end { -1 } else { 1 };
        var next = if e.code == key_home || e.code == key_end || c.popup_highlight < 0 { if direction > 0 { -1 } else { 0 } } else { c.popup_highlight };
        for attempt in items.len {
            next = (next + direction + items.len) % items.len;
            if !items[next].disabled && !items[next].separator { c.popup_highlight = next; break; }
        }
    }
    var action: i32 = -1;
    for i in items.len {
        if !items[i].disabled && !items[i].separator && (c.clicked == popup_item_id(owner, i) ||
            (e.kind == 5 && (e.code == key_enter || e.code == key_space) && c.popup_highlight == i)) { action = i as i32; }
    }
    if action >= 0 { c.popup = 0; focus(c, owner, c.keyboard_focus); c.changed = true; c.event = Event {}; return action; }
    let saved = c.parent; c.parent = -1;
    let panel = add(c, 12, ""); c.nodes[panel].id = mix(owner, 0x4d454e55);
    let w = min(width, max(120.0, c.width - 16.0));
    c.nodes[panel].box = Box { width: w, padding: 6.0, gap: 1.0, radius: c.theme.radius, clip: true, shadow: drop_shadow(12.0, 4.0, 0.4) };
    c.parent = panel;
    for i in items.len {
        let item = items[i];
        if item.separator { let line = add(c, 9, ""); c.nodes[line].box = Box { width: w - 12.0, height: 1.0 }; }
        else {
            let option = add(c, 13, ""); let n .= c.nodes[option];
            n.id = popup_item_id(owner, i); n.disabled = item.disabled;
            n.box = Box { width: w - 12.0, height: 26.0, padding: 5.0, clip: true };
            n.background = if c.popup_highlight == i { c.theme.accent } else { c.theme.surface };
            let color = if item.disabled { c.theme.muted } else { if c.popup_highlight == i { c.theme.accent_text } else { c.theme.text } };
            c.parent = option;
            row(c, Box { width: w - 22.0, align: 1 }) {
                text(c, item.label, TextOptions { color: color, size: 12.0, width: w - (if item.shortcut.len > 0 { 86.0 } else { 22.0 }) });
                if item.shortcut.len > 0 { spacer(c); text(c, item.shortcut, TextOptions { color: color, size: 11.0 }); }
            };
            end(c);
        }
    }
    for i: i32 in panel..c.count { c.nodes[i].overlay = true; }
    c.parent = saved; -1
}

fn popup_item_id(owner: u64, index: i64) -> u64 { mix(owner, 0x53454c4543540000 + index as u64) }
fn popup_visible_rows(c: Context&, anchor: Rect, count: i64, requested: i32) -> i32 {
    let available = max(anchor.y - 12.0, c.height - anchor.y - anchor.h - 12.0);
    min(count, min(requested as i64, max(1, ((available - 8.0) / 30.0) as! i64))) as i32
}
fn select(c: Context&, labels: const u8[:][:], selected: i64&, options: SelectOptions = SelectOptions {}) -> bool {
    assert(options.width > 0.0 && options.visible_rows > 0 && options.visible_rows <= 16);
    let current: i64 = selected;
    if labels.len > 0 { selected = clamp(current, 0, labels.len - 1); } else { selected = -1; }
    let i = add(c, 11, if selected >= 0 { labels[selected] } else { "No options" }, options.key);
    let n .= c.nodes[i]; n.box = Box { width: options.width, height: 34.0, radius: c.theme.radius };
    n.disabled = options.disabled || labels.len == 0;
    if n.disabled { if c.popup == n.id { c.popup = 0; } return false; }
    if c.popup_menu && c.popup == n.id { return false; }
    let was_open = c.popup == n.id; var commit = false;
    if c.clicked == n.id {
        c.popup_menu = false;
        c.popup = if was_open { 0 } else { n.id }; c.changed = true;
    }
    let e = c.event;
    if c.focus == n.id && e.kind == 5 {
        if e.code == key_enter || e.code == key_space || e.code == key_up || e.code == key_down {
            if !was_open { c.popup_menu = false; c.popup = n.id; c.changed = true; }
            else { if e.code == key_enter || e.code == key_space { commit = true; } }
        }
        if was_open {
            match e.code {
                key_down => { c.popup_highlight += 1; },
                key_up => { c.popup_highlight -= 1; },
                key_home => { c.popup_highlight = 0; },
                key_end => { c.popup_highlight = labels.len - 1; },
                key_page_up => { c.popup_highlight -= c.popup_rows; },
                key_page_down => { c.popup_highlight += c.popup_rows; },
                _ => {},
            }
        }
    }
    if c.popup != n.id { return false; }
    c.popup_count = labels.len;
    c.popup_rows = popup_visible_rows(c, prior_rect(c, n.id), labels.len, options.visible_rows);
    if !was_open {
        c.popup_wheel = 0.0;
        c.popup_highlight = selected;
        c.popup_first = clamp(selected - c.popup_rows + 1, 0, max(0, labels.len - c.popup_rows));
    }
    c.popup_highlight = clamp(c.popup_highlight, 0, labels.len - 1);
    if e.kind == 5 {
        c.popup_wheel = 0.0;
        if c.popup_highlight < c.popup_first { c.popup_first = c.popup_highlight; }
        if c.popup_highlight >= c.popup_first + c.popup_rows { c.popup_first = c.popup_highlight - c.popup_rows + 1; }
    }
    c.popup_first = clamp(c.popup_first, 0, max(0, labels.len - c.popup_rows));
    for index in c.popup_first..min(labels.len, c.popup_first + c.popup_rows) {
        if c.clicked == popup_item_id(n.id, index) { c.popup_highlight = index; commit = true; }
        if e.kind == 1 && c.hot == popup_item_id(n.id, index) { c.popup_highlight = index; }
    }
    if commit {
        let changed = selected != c.popup_highlight; selected = c.popup_highlight;
        c.popup = 0; focus(c, n.id, c.keyboard_focus); c.changed = true; return changed;
    }
    // Detached overlay nodes do not affect flex sizing or inherit scroll clips.
    let parent = c.parent; c.parent = -1;
    let panel = add(c, 12, "");
    c.nodes[panel].id = mix(n.id, 0x504f505550); c.nodes[panel].overlay = true;
    c.nodes[panel].box = Box { radius: c.theme.radius, shadow: drop_shadow(12.0, 5.0, 0.4) };
    for index in c.popup_first..min(labels.len, c.popup_first + c.popup_rows) {
        let item = add(c, 13, labels[index]); let option .= c.nodes[item];
        option.id = popup_item_id(n.id, index); option.overlay = true;
        option.value = (index - c.popup_first) as f32; option.checked = index == selected;
        option.background = if index == c.popup_highlight { c.theme.accent } else { c.theme.surface };
        option.color = if index == c.popup_highlight { c.theme.accent_text } else { c.theme.text };
    }
    c.parent = parent; false
}
fn layout_popup(c: Context&) {
    if c.popup == 0 || c.popup_menu { return; }
    var owner: i32 = -1;
    for i: i32 in c.count { if c.nodes[i].kind == 11 && c.nodes[i].id == c.popup && !c.nodes[i].disabled { owner = i; } }
    if owner < 0 { c.popup = 0; return; }
    let anchor = c.nodes[owner].rect;
    let owner_clip = intersect(anchor, c.nodes[owner].clip_rect);
    if owner_clip.w <= 0.0 || owner_clip.h <= 0.0 { c.popup = 0; return; }
    c.popup_anchor = anchor;
    c.popup_rows = popup_visible_rows(c, anchor, c.popup_count, c.popup_rows);
    let w = min(anchor.w, max(1.0, c.width - 16.0)); let h = c.popup_rows * 30.0 + 8.0;
    let below = c.height - anchor.y - anchor.h - 12.0;
    let above = anchor.y - 12.0;
    let y = if h > below && above > below { anchor.y - h - 4.0 } else { anchor.y + anchor.h + 4.0 };
    let panel = Rect { clamp(anchor.x, 8.0, max(8.0, c.width - w - 8.0)), clamp(y, 8.0, max(8.0, c.height - h - 8.0)), w, h };
    c.popup_rect = panel;
    let window = Rect { 0.0, 0.0, c.width, c.height };
    for i: i32 in c.count {
        let n .= c.nodes[i];
        if n.kind == 12 { n.rect = panel; n.clip_rect = window; }
        if n.kind == 13 {
            n.rect = Rect { panel.x + 4.0, panel.y + 4.0 + n.value * 30.0, max(0.0, panel.w - 8.0), 30.0 };
            n.clip_rect = intersect(window, inset(panel, 4.0));
        }
    }
}
fn option_rect(c: Context&, index: i64) -> Rect {
    let id = popup_item_id(c.popup, index);
    for i: i32 in c.count { if c.nodes[i].kind == 13 && c.nodes[i].id == id { return c.nodes[i].rect; } }
    assert(false); Rect {}
}
