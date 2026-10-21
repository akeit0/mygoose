namespace mygoose;
import ui;

struct DividerOptions { key: const u8[:] = "", width: f32 = 8.0, height: f32 = 25.0, step: f32 = 8.0 }
fn column_divider(c: Context&, width: f32&,
                  minimum: f32, maximum: f32, options: DividerOptions = DividerOptions {}) -> bool {
    let i = button_node(c, "", ButtonOptions { width: options.width, key: options.key,
        style: ButtonStyle { flat: true, radius: 0.0 } });
    let id = c.nodes[i].id; c.nodes[i].box.height = options.height; c.nodes[i].cursor = cursor_resize_horizontal;
    let old: f32 = width;
    let parent = c.nodes[i].parent;
    let drag = pointer_drag(c, i, old, Rect { w: c.nodes[parent].box.width, h: c.nodes[parent].box.height });
    if drag.update { width = clamp(drag.value + drag.dx, minimum, maximum); }
    if c.focus == id && c.event.kind == 5 && (c.event.code == key_left || c.event.code == key_right) {
        let current: f32 = width;
        let next = clamp(current + (if c.event.code == key_left { -options.step } else { options.step }), minimum, maximum);
        width = next;
    }
    let status = interaction(c, i);
    let highlighted = status.hovered || status.held || (status.focused && c.keyboard_focus);
    c.parent = i;
    row(c, Box { width: options.width, height: options.height, justify: 1, align: 1 }) {
        column(c, Box { width: 2.0, height: min(14.0, options.height), background: if highlighted { c.theme.accent } else { c.theme.border }, radius: 1.0 }) {};
    };
    end(c);
    if width != old { c.changed = true; } width != old
}
// Both axes share pointer capture. Callers own their offsets and data;
// a scrollbar needs no persistent drag record of its own.
struct ScrollbarOptions {
    key: const u8[:] = "", thickness: f32 = 12.0, step: f32 = 32.0,
    track: i64 = -1, thumb: i64 = -1, hover: i64 = -1
}
fn scrollbar(c: Context&, offset: f32&, length: f32, content: f32, vertical: bool,
             options: ScrollbarOptions = ScrollbarOptions {}) {
    assert(length > 1.0 && options.thickness > 0.0);
    let limit = max(0.0, content - length);
    if limit <= 0.0 { offset = 0.0; return; }
    let thumb = min(length - 1.0, max(24.0, length * length / content)); let travel = length - thumb;
    let track: i64 = if options.track >= 0 { options.track } else { c.theme.surface };
    let i = button_node(c, "", ButtonOptions { width: if vertical { options.thickness } else { length }, key: options.key,
        style: ButtonStyle { flat: true, background: track, hover: track, pressed: track, radius: 5.0 } });
    c.nodes[i].box.height = if vertical { length } else { options.thickness }; c.nodes[i].box.clip = true;
    let id = c.nodes[i].id; let r = prior_rect(c, id); let old: f32 = offset;
    let mouse = if vertical { c.mouse_y } else { c.mouse_x }; let start = if vertical { r.y } else { r.x };
    let status = interaction(c, i);
    if status.pressed && r.w > 0.0 {
        let left = start + offset / limit * travel;
        if mouse < left || mouse >= left + thumb { offset = clamp((mouse - start - thumb * 0.5) / travel, 0.0, 1.0) * limit; }
    }
    let drag = pointer_drag(c, i, offset, Rect { x: r.x, y: r.y, w: length, h: content });
    if drag.update && r.w > 0.0 { offset = clamp(drag.value + (if vertical { drag.dy } else { drag.dx }) / travel * limit, 0.0, limit); }
    if c.focus == id && c.event.kind == 5 {
        if c.event.code == (if vertical { key_up } else { key_left }) { offset -= options.step; }
        if c.event.code == (if vertical { key_down } else { key_right }) { offset += options.step; }
        if c.event.code == key_home { offset = 0.0; } if c.event.code == key_end { offset = limit; }
    }
    let current: f32 = offset; offset = clamp(current, 0.0, limit);
    if offset != old { c.changed = true; }
    let tint = if c.hot == id || c.active == id { if options.hover >= 0 { options.hover as u32 } else { c.theme.muted } }
        else { if options.thumb >= 0 { options.thumb as u32 } else { c.theme.border } };
    c.parent = i; let position = offset / limit * travel;
    if vertical {
        column(c, Box { width: options.thickness, height: length, align: 1 }) {
            column(c, Box { width: 1.0, height: position }) {};
            column(c, Box { width: min(6.0, options.thickness), height: thumb, background: tint, radius: 3.0 }) {};
        };
    } else {
        row(c, Box { width: length, height: options.thickness, align: 1 }) {
            column(c, Box { width: position, height: 1.0 }) {};
            column(c, Box { width: thumb, height: min(6.0, options.thickness), background: tint, radius: 3.0 }) {};
        };
    }
    end(c);
}
fn horizontal_scrollbar(c: Context&, offset: f32&, width: f32, content: f32,
                        options: ScrollbarOptions = ScrollbarOptions {}) { scrollbar(c, offset, width, content, false, options); }

struct ScrollAreaState { offset: f32 = 0.0, content: f32 = 0.0 }
struct ScrollViewport { outer: i32 = 0, content: i32 = 0, width: f32 = 0.0, height: f32 = 0.0 }
struct ScrollAreaOptions {
    key: const u8[:] = "", step: f32 = 72.0, gap: f32 = 14.0,
    padding: f32 = 0.0, scrollbar: ScrollbarOptions = ScrollbarOptions {}
}
fn begin_scroll_area(c: Context&, state: ScrollAreaState&, box: Box, options: ScrollAreaOptions = ScrollAreaOptions {}) -> ScrollViewport {
    assert(box.width > options.scrollbar.thickness + 6.0 && box.height > 1.0);
    row(c, Box { width: box.width, height: box.height, gap: 6.0, background: box.background, radius: box.radius }, options.key);
    let previous = prior_rect(c, c.nodes[c.parent].id);
    let width = box.width - options.scrollbar.thickness - 6.0;
    column(c, Box { width: width, height: box.height, clip: true }, "viewport"); let outer = c.parent;
    if c.event.kind == 4 && contains(previous, c.mouse_x, c.mouse_y) { state.offset -= scroll_distance(c.event, options.step); }
    state.offset = clamp(state.offset, 0.0, max(0.0, state.content - box.height)); c.nodes[outer].value = -state.offset;
    column(c, Box { width: width, gap: options.gap, padding: options.padding }, "content");
    ScrollViewport { outer: outer, content: c.parent, width: width, height: box.height }
}
fn end_scroll_area(c: Context&, state: ScrollAreaState&, page: ScrollViewport, options: ScrollAreaOptions = ScrollAreaOptions {}) {
    end(c); measure(c, page.content); state.content = c.nodes[page.content].measured_h;
    let old = state.offset;
    state.offset = clamp(state.offset, 0.0, max(0.0, state.content - page.height)); c.nodes[page.outer].value = -state.offset;
    if state.offset != old { c.changed = true; }
    end(c);
    if state.content > page.height { scrollbar(c, state.offset, page.height, state.content, true, options.scrollbar); }
    else { column(c, Box { width: options.scrollbar.thickness, height: page.height }) {}; }
    end(c);
}
fn scroll_area<Children>(c: Context&, state: ScrollAreaState&, box: Box, options: ScrollAreaOptions = ScrollAreaOptions {}) {
    let page = begin_scroll_area(c, state, box, options); Children(page.width); end_scroll_area(c, state, page, options);
}
