namespace mygoose;
import std;
import .geom;
import .ui;
import .select;
import .damage;

extern fn mg_paint_begin(x: f32, y: f32, w: f32, h: f32, background: u32);
extern fn mg_paint_regions(rects: const Rect[:], background: u32) -> bool;
extern fn mg_paint_end();
extern fn mg_clip(x: f32, y: f32, w: f32, h: f32);
extern fn mg_rect(x: f32, y: f32, w: f32, h: f32, radius: f32, color: u32);
extern fn mg_shadow(x: f32, y: f32, w: f32, h: f32, radius: f32, blur: f32, spread: f32, dx: f32, dy: f32, color: u32, opacity: f32);
extern fn mg_text(text: const u8[:], x: f32, y: f32, size: f32, bold: bool, color: u32);
extern fn mg_ime_anchor(owner: u64, x: f32, y: f32, w: f32, h: f32, font_size: f32);

recursive fn measure(c: Context&, i: i32) {
    let n .= c.nodes[i];
    var w: f32 = 0.0; var h: f32 = 0.0; var child = n.first; var count: i32 = 0;
    while child >= 0 {
        measure(c, child); let ch .= c.nodes[child];
        if n.kind == 1 { w += ch.measured_w; h = max(h, ch.measured_h); }
        else { w = max(w, ch.measured_w); h += ch.measured_h; }
        count += 1; child = ch.next;
    }
    if count > 1 { if n.kind == 1 { w += (count - 1) * n.box.gap; } else { h += (count - 1) * n.box.gap; } }
    if ((n.kind >= 2 && n.kind <= 9) || n.kind == 11 || n.kind == kind_selectable_row) && !(button_kind(n) && n.first >= 0) {
        w = text_width(c, node_text(c, i), n.size, n.bold); h = n.size * 1.4;
        if button_kind(n) { w += 28.0; }
        if n.kind == 11 { w += 44.0; }
        if n.kind == 4 { w += 28.0; h = max(h, 24.0); }
        if n.kind == 5 { w += 50.0; h = max(h, 24.0); }
    }
    w += n.box.padding * 2.0; h += n.box.padding * 2.0;
    n.measured_w = if n.box.width > 0.0 { n.box.width } else { w };
    n.measured_h = if n.box.height > 0.0 { n.box.height } else { h };
}
recursive fn arrange(c: Context&, i: i32, rect: Rect, clip: Rect) {
    let n .= c.nodes[i]; n.rect = rect; n.clip_rect = clip;
    let inner = inset(rect, n.box.padding);
    let child_clip = if n.box.clip { intersect(clip, rect) } else { clip };
    var child = n.first; var used: f32 = 0.0; var weight: f32 = 0.0; var count: i32 = 0;
    while child >= 0 {
        let ch .= c.nodes[child]; let g = if ch.box.fill { max(1.0, ch.box.grow) } else { ch.box.grow };
        weight += g;
        used += if n.kind == 1 { ch.measured_w } else { ch.measured_h };
        count += 1; child = ch.next;
    }
    let axis = if n.kind == 1 { inner.w } else { inner.h };
    var gap = n.box.gap; used += max(0, count - 1) * gap;
    let free = max(0.0, axis - used); var pos: f32 = 0.0;
    let justify = if n.box.center { 1 } else { n.box.justify };
    if weight == 0.0 {
        match justify {
            1 => { pos = free * 0.5; },
            2 => { pos = free; },
            3 => { if count > 1 { gap += free / (count - 1); } },
            _ => {},
        }
    }
    if n.box.clip && !button_kind(n) { pos += n.value; }
    child = n.first;
    while child >= 0 {
        let ch .= c.nodes[child];
        let g = if ch.box.fill { max(1.0, ch.box.grow) } else { ch.box.grow };
        let extra = if weight > 0.0 { free * g / weight } else { 0.0 };
        var w = ch.measured_w; var h = ch.measured_h;
        let align = if n.box.center { 1 } else { n.box.align };
        if n.kind == 1 {
            w += extra;
            if ch.box.fill || (align == 3 && ch.box.height == 0.0) { h = inner.h; }
            let cross = match align { 1 => (inner.h - h) * 0.5, 2 => inner.h - h, _ => 0.0 };
            arrange(c, child, Rect { inner.x + pos, inner.y + cross, max(0.0, w), max(0.0, h) }, child_clip); pos += w + gap;
        } else {
            h += extra;
            if ch.box.fill || (align == 3 && ch.box.width == 0.0) { w = inner.w; }
            let cross = match align { 1 => (inner.w - w) * 0.5, 2 => inner.w - w, _ => 0.0 };
            arrange(c, child, Rect { inner.x + cross, inner.y + pos, max(0.0, w), max(0.0, h) }, child_clip); pos += h + gap;
        }
        child = ch.next;
    }
}
fn finish(c: Context&) {
    assert(c.parent == 0); c.parent = -1;
    measure(c, 0); arrange(c, 0, Rect { 0.0, 0.0, c.width, c.height }, Rect { 0.0, 0.0, c.width, c.height });
    layout_popup(c);
    layout_context_menu(c);
    c.hot = hit(c, c.mouse_x, c.mouse_y);
    reconcile_interaction(c);
    let pointer = if c.active != 0 { c.active } else { c.hot };
    var cursor: i32 = 0;
    if c.event.kind != 7 { for i: i32 in c.count { if c.nodes[i].id == pointer && !c.nodes[i].disabled { cursor = c.nodes[i].cursor; break; } } }
    mg_cursor(cursor);
    sync_ime(c);
    finish_animations(c.animations);
    c.frames += 1;
}
fn layout_context_menu(c: Context&) {
    if c.popup == 0 || !c.popup_menu { return; }
    var owner: i32 = -1; var panel: i32 = -1;
    for i: i32 in c.count {
        if c.nodes[i].id == c.popup && focusable(c.nodes[i]) { owner = i; }
        if c.nodes[i].kind == 12 && c.nodes[i].id == mix(c.popup, 0x4d454e55) { panel = i; }
    }
    if owner < 0 || panel < 0 { c.popup = 0; return; }
    measure(c, panel);
    let w = min(c.nodes[panel].measured_w, max(1.0, c.width - 16.0));
    let h = min(c.nodes[panel].measured_h, max(1.0, c.height - 16.0));
    c.popup_rect = Rect { clamp(c.popup_anchor.x, 8.0, max(8.0, c.width - w - 8.0)), clamp(c.popup_anchor.y, 8.0, max(8.0, c.height - h - 8.0)), w, h };
    arrange(c, panel, c.popup_rect, Rect { w: c.width, h: c.height });
}
fn sync_ime(c: Context&) {
    for i: i32 in c.count {
        let n .= c.nodes[i];
        if n.ime_owner != 0 && n.ime_owner == c.focus && n.caret >= 0.0 {
            let r = n.rect;
            let clip = intersect(n.clip_rect, if n.kind == 8 { inset(r, 5.0) } else { r });
            let y = if n.kind == 8 { r.y + (r.h - n.size * 1.4) * 0.5 } else { r.y };
            let h = n.size * 1.4;
            if clip.w > 1.0 && clip.h > 1.0 && y + h > clip.y && y < clip.y + clip.h {
                let x = r.x + (if n.kind == 8 { 8.0 } else { 0.0 }) - n.text_scroll + n.ime_x;
                mg_ime_anchor(c.focus, clamp(x, clip.x, clip.x + clip.w - 1.0), max(y, clip.y),
                    1.0, min(h, clip.y + clip.h - max(y, clip.y)), n.size);
                return;
            }
        }
    }
    mg_ime_anchor(0, 0.0, 0.0, 1.0, 1.0, c.theme.font_size);
}
fn render_hash(c: Context&, i: i32) -> u64 {
    let n .= c.nodes[i]; var h = hash_text(node_text(c, i));
    // The hash is an optimization. Geometry is compared exactly as well.
    h = mix(h, n.kind as u64); h = mix(h, n.color); h = mix(h, n.background);
    h = mix(h, (n.value * 65536.0) as! i64 as! u64);
    h = mix(h, (n.size * 64.0) as! u64); h = mix(h, (n.box.radius * 64.0) as! u64);
    h = mix(h, n.box.background); h = mix(h, if n.box.opaque { 1 } else { 0 }); h = mix(h, if n.bold { 1 } else { 0 });
    h = mix(h, n.box.align as! u64);
    if button_kind(n) { h = mix(h, (n.box.padding * 64.0) as! u64); }
    h = mix(h, if n.checked { 1 } else { 0 }); h = mix(h, if n.disabled { 1 } else { 0 });
    h = mix(h, if n.id == c.focus { 1 } else { 0 }); h = mix(h, if n.id == c.hot { 1 } else { 0 });
    h = mix(h, if n.id == c.active { 1 } else { 0 });
    if button_kind(n) { h = mix(h, if button_focused(c, i) && c.keyboard_focus { 1 } else { 0 }); }
    h = mix(h, (n.caret * 64.0) as! i64 as! u64); h = mix(h, (n.selection_x * 64.0) as! u64);
    h = mix(h, (n.selection_w * 64.0) as! u64);
    h = mix(h, (n.text_scroll * 64.0) as! u64);
    h = mix(h, (n.composition_x * 64.0) as! u64); h = mix(h, (n.composition_w * 64.0) as! u64);
    h = mix(h, (n.target_x * 64.0) as! u64); h = mix(h, (n.target_w * 64.0) as! u64);
    let s = n.box.shadow;
    h = mix(h, (s.blur * 64.0) as! i64 as! u64); h = mix(h, (s.spread * 64.0) as! i64 as! u64);
    h = mix(h, (s.x * 64.0) as! i64 as! u64); h = mix(h, (s.y * 64.0) as! i64 as! u64);
    h = mix(h, s.color); h = mix(h, (s.opacity * 65536.0) as! u64);
    h = mix(h, if n.overlay { 1 } else { 0 });
    h
}
fn same_rect(a: Rect, b: Rect) -> bool { a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h }
// Separate scene hashes from IDs, which input needs even before a frame paints.
struct SceneCache {
    hashes: u64[1024] = [0; 1024], clips: Rect[1024] = [Rect {}; 1024],
    bounds: Rect[1024] = [Rect {}; 1024], theme_hash: u64 = 0
}
fn paint_bounds(n: Node&) -> Rect {
    let s = n.box.shadow;
    if s.opacity <= 0.0 { return n.rect; }
    assert(s.blur >= 0.0 && s.blur <= 64.0 && s.spread >= 0.0 && s.spread <= 64.0 && s.opacity <= 1.0);
    let extent = s.blur + s.spread + 1.0; let r = n.rect;
    unite(r, Rect { r.x + s.x - extent, r.y + s.y - extent, r.w + extent * 2.0, r.h + extent * 2.0 })
}
// Preserve the Context entry point for custom frame loops; storage and merging
// live in the geometry module and never need a scene or a native window.
fn add_damage(c: Context&, rect: Rect) {
    let r = intersect(rect, Rect { w: c.width, h: c.height });
    if r.w <= 0.0 || r.h <= 0.0 { return; }
    let follow_regions = same_rect(c.dirty, c.regions.bounds);
    add_damage(c.regions, r);
    c.dirty = if follow_regions { c.regions.bounds } else { unite(c.dirty, r) };
    c.paint_regions = 0;
}
fn damage(c: Context&, cache: SceneCache&) -> bool {
    c.dirty = Rect {}; clear_damage(c.regions); c.paint_regions = 0;
    var theme_hash = mix(c.theme.background, c.theme.surface);
    theme_hash = mix(theme_hash, c.theme.hover); theme_hash = mix(theme_hash, c.theme.pressed);
    theme_hash = mix(theme_hash, c.theme.border); theme_hash = mix(theme_hash, c.theme.text);
    theme_hash = mix(theme_hash, c.theme.muted); theme_hash = mix(theme_hash, c.theme.accent);
    theme_hash = mix(theme_hash, c.theme.accent_text); theme_hash = mix(theme_hash, (c.theme.radius * 64.0) as! u64);
    if c.force || cache.theme_hash != theme_hash { add_damage(c, Rect { 0.0, 0.0, c.width, c.height }); }
    cache.theme_hash = theme_hash;
    for i: i32 in max(c.count, c.previous_count) {
        if i >= c.count { add_damage(c, intersect(cache.bounds[i], cache.clips[i])); }
        else {
            let n .= c.nodes[i]; let h = render_hash(c, i);
            if i >= c.previous_count || cache.hashes[i] != h || !same_rect(c.previous[i].rect, n.rect) || !same_rect(cache.clips[i], n.clip_rect) {
                if i < c.previous_count { add_damage(c, intersect(cache.bounds[i], cache.clips[i])); }
                add_damage(c, intersect(paint_bounds(n), n.clip_rect));
            }
            cache.hashes[i] = h; cache.clips[i] = n.clip_rect; cache.bounds[i] = paint_bounds(n); c.previous[i] = Stamp { n.id, n.rect };
        }
    }
    c.previous_count = c.count; c.force = false; c.last_background = c.theme.background;
    c.dirty.w > 0.0 && c.dirty.h > 0.0
}
fn damage_bounds(c: Context&) -> Rect { c.regions.bounds }
// Query after paint, before the next damage calculation. Fallback backends and
// explicit dirty overrides paint the bounding rectangle, not a sparse union.
fn paint_area(c: Context&) -> f32 {
    if c.paint_regions == 0 { return 0.0; }
    if c.paint_regions > 1 { return damage_area(c.regions); }
    rect_area(c.dirty)
}
fn draw_rect(r: Rect, radius: f32, color: u32) { if r.w > 0.0 && r.h > 0.0 { mg_rect(r.x, r.y, r.w, r.h, radius, color); } }
fn transition_color(from: u32, target: u32, amount: f32) -> u32 {
    var color: u32 = 0;
    for shift in [0, 8, 16] {
        let a = ((from >> shift) & 255) as! f32; let b = ((target >> shift) & 255) as! f32;
        color |= ((a + (b - a) * amount + 0.5) as! u32) << shift;
    }
    color
}
fn no_extra_paint(c: Context&, index: i32) {}
fn paint(c: Context&) { paint(c, no_extra_paint); }
// Optional modules supply a compile-time painter; the basic specialization
// erases this callback and needs no extension storage in Context or Node.
fn paint<Extra>(c: Context&) {
    let d = c.dirty;
    // Manual dirty rectangles remain supported. Backends may choose one bounding
    // rectangle; only cull gaps when native clipping preserves them as well.
    let regions = c.regions.rects.len > 0 && same_rect(d, damage_bounds(c));
    var segmented = false;
    if regions { segmented = mg_paint_regions(c.regions.rects[..], c.theme.background); }
    else { mg_paint_begin(d.x, d.y, d.w, d.h, c.theme.background); }
    c.paint_regions = if segmented { c.regions.rects.len as i32 } else { 1 };
    for layer in 2 { for i: i32 in c.count {
        let n .= c.nodes[i]; let r = n.rect; let clip = intersect(n.clip_rect, d);
        if n.overlay != (layer == 1) { continue; }
        // Native clips round out to pixels. A control just beyond the logical
        // damage edge can still contribute to that boundary pixel.
        let bounds = paint_bounds(n);
        let visible = intersect(Rect { bounds.x - 1.0, bounds.y - 1.0, bounds.w + 2.0, bounds.h + 2.0 }, clip);
        if visible.w <= 0.0 || visible.h <= 0.0 { continue; }
        if segmented && !touches_damage(c.regions, visible) { continue; }
        mg_clip(clip.x, clip.y, clip.w, clip.h);
        let shadow = n.box.shadow;
        if shadow.opacity > 0.0 { mg_shadow(r.x, r.y, r.w, r.h, n.box.radius, shadow.blur, shadow.spread, shadow.x, shadow.y, shadow.color, shadow.opacity); }
        let color = if n.disabled { c.theme.muted } else { n.color };
        let text_y = r.y + (r.h - n.size * 1.4) * 0.5;
        if n.box.background != 0 || n.box.opaque { draw_rect(r, n.box.radius, n.box.background); }
        if n.kind == 2 {
            let free = if n.box.align != 0 { max(0.0, r.w - text_width(c, node_text(c, i), n.size, n.bold)) } else { 0.0 };
            let x = r.x + (if n.box.align == 1 { free * 0.5 } else { free }) - n.text_scroll;
            let text_clip = intersect(clip, r); mg_clip(text_clip.x, text_clip.y, text_clip.w, text_clip.h);
            if n.selection_w > 0.0 { draw_rect(Rect { x + n.selection_x, r.y, n.selection_w, n.size * 1.4 }, 0.0, c.theme.accent); }
            if n.target_w > 0.0 { draw_rect(Rect { x + n.target_x, r.y, n.target_w, n.size * 1.4 }, 0.0, c.theme.accent); }
            mg_text(node_text(c, i), x, r.y, n.size, n.bold, color);
            if n.composition_w > 0.0 { draw_rect(Rect { x + n.composition_x, r.y + n.size * 1.4 - 1.0, n.composition_w, 1.0 }, 0.0, c.theme.text); }
            if n.caret >= 0.0 { draw_rect(Rect { x + n.caret, r.y, 1.0, n.size * 1.4 }, 0.0, c.theme.text); }
        }
        if n.kind == 10 && n.id == c.focus { draw_rect(Rect { r.x, r.y, r.w, 1.0 }, 0.0, c.theme.accent); }
        if button_kind(n) || n.kind == 8 || n.kind == 11 {
            let input_flat = n.kind == 8 && n.value == 2.0;
            let flat = button_kind(n) && n.value == 2.0;
            let focus = button_focused(c, i) && (!flat || c.keyboard_focus);
            let radius = if button_kind(n) { n.box.radius } else { c.theme.radius };
            let bg = if button_kind(n) && (n.value >= 1.0) { n.background } else {
                if n.id == c.active { c.theme.pressed } else { if n.id == c.hot { c.theme.hover } else { n.background } }
            };
            if !input_flat {
                if !flat || focus {
                    draw_rect(r, radius, if focus { c.theme.accent } else { c.theme.border });
                    draw_rect(inset(r, 1.0), max(0.0, radius - 1.0), bg);
                } else { draw_rect(r, radius, bg); }
            }
            let text_box = if n.kind == 11 { Rect { r.x + 5.0, r.y + 5.0, max(0.0, r.w - 33.0), max(0.0, r.h - 10.0) } } else { if flat { r } else { inset(r, 5.0) } };
            let inside = intersect(clip, text_box); mg_clip(inside.x, inside.y, inside.w, inside.h);
            let width = if button_kind(n) { text_width(c, node_text(c, i), n.size, n.bold) } else { 0.0 };
            let padding = if flat { n.box.padding } else { 8.0 };
            let x = if button_kind(n) {
                if (n.value >= 1.0) && n.box.align == 0 { r.x + padding } else {
                    if (n.value >= 1.0) && n.box.align == 2 { r.x + r.w - width - padding } else { r.x + (r.w - width) * 0.5 }
                }
            } else { r.x + 8.0 - n.text_scroll };
            if n.selection_w > 0.0 { draw_rect(Rect { x + n.selection_x, text_y, n.selection_w, n.size * 1.4 }, 0.0, c.theme.accent); }
            if n.target_w > 0.0 { draw_rect(Rect { x + n.target_x, text_y, n.target_w, n.size * 1.4 }, 0.0, c.theme.accent); }
            mg_text(node_text(c, i), x, text_y, n.size, n.bold, color);
            if n.kind == 11 { mg_clip(clip.x, clip.y, clip.w, clip.h); mg_text("⌄", r.x + r.w - 22.0, text_y, n.size, false, color); }
            if n.composition_w > 0.0 { draw_rect(Rect { x + n.composition_x, text_y + n.size * 1.4 - 1.0, n.composition_w, 1.0 }, 0.0, c.theme.text); }
            if n.caret >= 0.0 { draw_rect(Rect { x + n.caret, text_y + 1.0, 1.0, n.size * 1.4 - 2.0 }, 0.0, c.theme.text); }
        }
        if n.kind == 4 || n.kind == 5 {
            let w: f32 = if n.kind == 4 { 18.0 } else { 36.0 }; let y = r.y + (r.h - 18.0) * 0.5;
            let track = if n.kind == 5 { transition_color(c.theme.border, c.theme.accent, n.value) }
                else { if n.checked { c.theme.accent } else { c.theme.border } };
            draw_rect(Rect { r.x, y, w, 18.0 }, if n.kind == 4 { 4.0 } else { 9.0 }, track);
            if n.kind == 5 { draw_rect(Rect { r.x + 2.0 + 18.0 * n.value, y + 2.0, 14.0, 14.0 }, 7.0, 0xffffff); }
            else { if n.checked { mg_text("✓", r.x + 3.0, y - 1.0, 14.0, true, 0xffffff); } }
            mg_text(node_text(c, i), r.x + w + 10.0, text_y, n.size, false, color);
            if n.id == c.focus { draw_rect(Rect { r.x + w + 10.0, r.y + r.h - 2.0, max(0.0, r.w - w - 10.0), 1.0 }, 0.0, c.theme.accent); }
        }
        if n.kind == 6 || n.kind == 7 {
            let h: f32 = if n.kind == 6 { 4.0 } else { r.h }; let y = r.y + (r.h - h) * 0.5;
            draw_rect(Rect { r.x, y, r.w, h }, h * 0.5, c.theme.border);
            draw_rect(Rect { r.x, y, r.w * n.value, h }, h * 0.5, c.theme.accent);
            if n.kind == 6 { draw_rect(Rect { r.x + (r.w - 12.0) * n.value, r.y + (r.h - 12.0) * 0.5, 12.0, 12.0 }, 6.0, if n.id == c.focus { c.theme.text } else { c.theme.accent }); }
        }
        if n.kind == 9 { draw_rect(r, 0.0, c.theme.border); }
        if n.kind == 12 { draw_rect(r, c.theme.radius, c.theme.border); draw_rect(inset(r, 1.0), max(0.0, c.theme.radius - 1.0), c.theme.surface); }
        if n.kind == 13 {
            draw_rect(r, max(0.0, c.theme.radius - 2.0), n.background);
            let inside = intersect(clip, inset(r, 4.0)); mg_clip(inside.x, inside.y, inside.w, inside.h);
            mg_text(node_text(c, i), r.x + 8.0, text_y, n.size, false, n.color);
            if n.checked { mg_text("✓", r.x + r.w - 22.0, text_y, n.size, false, n.color); }
        }
        Extra(c, i);
    } }
    mg_paint_end(); c.paints += 1;
}
// Use only for a leaf's own bounds, after checking its kind. The native
// backend preserves the frame's damage union while applying this clip.
fn clip_leaf(c: Context&, index: i32) -> bool {
    let n .= c.nodes[index]; let r = intersect(intersect(c.dirty, n.clip_rect), n.rect);
    if r.w <= 0.0 || r.h <= 0.0 { return false; }
    mg_clip(r.x, r.y, r.w, r.h); true
}
fn build_frame<T, View>(c: Context&, state: T&, width: f32, height: f32) {
    begin(c, width, height); View(state, c); finish(c); let changed = c.changed;
    let frame_ns = c.frame_ns;
    finish_input(c);
    if changed { begin(c, width, height); c.frame_ns = frame_ns; View(state, c); finish(c); }
    if !c.scroll_seen { c.scroll_owner = 0; }
    mg_animation_pending(c.scroll_owner != 0 || c.animations.active);
}
