namespace mygoose;
import std;

struct Rect { x: f32 = 0.0, y: f32 = 0.0, w: f32 = 0.0, h: f32 = 0.0 }
fn contains(r: Rect, x: f32, y: f32) -> bool {
    r.w > 0.0 && r.h > 0.0 && x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}
fn intersect(a: Rect, b: Rect) -> Rect {
    let x = max(a.x, b.x); let y = max(a.y, b.y);
    Rect { x, y, max(0.0, min(a.x + a.w, b.x + b.w) - x), max(0.0, min(a.y + a.h, b.y + b.h) - y) }
}
fn unite(a: Rect, b: Rect) -> Rect {
    if a.w <= 0.0 || a.h <= 0.0 { return b; }
    if b.w <= 0.0 || b.h <= 0.0 { return a; }
    let x = min(a.x, b.x); let y = min(a.y, b.y);
    Rect { x, y, max(a.x + a.w, b.x + b.w) - x, max(a.y + a.h, b.y + b.h) - y }
}
fn inset(r: Rect, p: f32) -> Rect { Rect { r.x + p, r.y + p, max(0.0, r.w - p * 2.0), max(0.0, r.h - p * 2.0) } }
fn hash_text(s: const u8[:], seed: u64 = 14695981039346656037) -> u64 {
    var h = seed;
    for b in s { h = (h ^ b) * 1099511628211; }
    if h == 0 { return 1; } return h;
}
fn mix(h: u64, n: u64) -> u64 { (h ^ n) * 1099511628211 }

struct Theme {
    background: u32 = 0x18181b, surface: u32 = 0x27272a,
    hover: u32 = 0x353539, pressed: u32 = 0x45454b,
    border: u32 = 0x52525b, text: u32 = 0xfafafa, muted: u32 = 0xa1a1aa,
    accent: u32 = 0x3b82f6, accent_text: u32 = 0xffffff,
    radius: f32 = 6.0, font_size: f32 = 14.0
}
fn light_theme() -> Theme {
    Theme { background: 0xffffff, surface: 0xf4f4f5, hover: 0xe4e4e7,
        pressed: 0xd4d4d8, border: 0xa1a1aa, text: 0x18181b, muted: 0x71717a, accent: 0x2563eb }
}
