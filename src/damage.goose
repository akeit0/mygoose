namespace mygoose;
import geom;
import std;

let max_damage_regions: i32 = 16;
// Region geometry is independent of the scene tree and native renderer.
// The bounded array owns its length; there is no separate counter to reconcile.
struct DamageRegions {
    rects: Rect[..max_damage_regions] = [], bounds: Rect = Rect {}
}
fn clear_damage(regions: DamageRegions&) { regions.rects.clear(); regions.bounds = Rect {}; }
fn rect_area(rect: Rect) -> f32 { max(0.0, rect.w) * max(0.0, rect.h) }
fn add_damage(regions: DamageRegions&, rect: Rect) {
    if rect.w <= 0.0 || rect.h <= 0.0 { return; }
    var r = rect;
    loop {
        var i: i64 = 0;
        while i < regions.rects.len {
            let old = regions.rects[i]; let joined = unite(r, old);
            if rect_area(joined) <= (rect_area(r) + rect_area(old)) * 1.15 {
                r = joined; swap_remove(regions.rects, i); i = 0;
            } else { i += 1; }
        }
        if regions.rects.len < regions.rects.cap {
            regions.rects.push(r); regions.bounds = unite(regions.bounds, r); return;
        }
        var best: i64 = 0; var cost: f32 = 1.0e30;
        for old, j in regions.rects {
            let extra = rect_area(unite(r, old)) - rect_area(old);
            if extra < cost { cost = extra; best = j; }
        }
        r = unite(r, swap_remove(regions.rects, best));
        // Reconsider the enlarged region without recursion or extra storage.
    }
}
fn touches_damage(regions: DamageRegions&, rect: Rect) -> bool {
    for region in regions.rects {
        // Native clips round outward. Logical gaps can share a boundary pixel.
        let part = intersect(rect, inset(region, -1.0));
        if part.w > 0.0 && part.h > 0.0 { return true; }
    } false
}
struct DamageSpan { lo: f32, hi: f32 }
// Exact logical union area, including overlapping regions. Only callers that
// request this diagnostic pay for the bounded sweep; ordinary paints do not.
fn damage_area(regions: DamageRegions&) -> f32 {
    if regions.rects.len == 0 { return 0.0; }
    if regions.rects.len == 1 { return rect_area(regions.rects[0]); }
    var sum: f32 = 0.0; var overlaps = false;
    for r, i in regions.rects {
        sum += rect_area(r);
        for j in 0..i {
            let part = intersect(r, regions.rects[j]);
            if part.w > 0.0 && part.h > 0.0 { overlaps = true; }
        }
    }
    if !overlaps { return sum; }
    var edges: f32[..max_damage_regions * 2] = [];
    for r in regions.rects { edges.push(r.x); edges.push(r.x + r.w); }
    sort_insertion(edges) { a, b => a < b }
    var total: f32 = 0.0;
    for i in 1..edges.len {
        let left = edges[i - 1]; let right = edges[i];
        if right <= left { continue; }
        var spans: DamageSpan[..max_damage_regions] = [];
        for r in regions.rects {
            if r.x < right && r.x + r.w > left { spans.push(DamageSpan { r.y, r.y + r.h }); }
        }
        if spans.len == 0 { continue; }
        sort_insertion(spans) { a, b => a.lo < b.lo }
        var end = spans[0].lo; var covered: f32 = 0.0;
        for span in spans {
            if span.hi > end { covered += span.hi - max(end, span.lo); end = span.hi; }
        }
        total += (right - left) * covered;
    }
    total
}
