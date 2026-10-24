namespace mygoose;
import std;

let max_animations: i32 = 128;
struct Transition { duration_ms: f32 = 160.0 }
struct AnimationTrack {
    id: u64 = 0, channel: u64 = 0, seen: i64 = 0,
    from: f32 = 0.0, target: f32 = 0.0, value: f32 = 0.0,
    start_ns: i64 = 0, duration_ns: i64 = 0
}
struct AnimationCache {
    tracks: AnimationTrack[128] = [AnimationTrack {}; 128],
    count: i32 = 0, pass: i64 = 0, active: bool = false
}
fn sample_animation(t: AnimationTrack&, now_ns: i64) -> f32 {
    if t.duration_ns <= 0 { return t.target; }
    let elapsed = clamp((now_ns - t.start_ns) / t.duration_ns as f64, 0.0, 1.0);
    let remaining = 1.0 - elapsed;
    (t.from + (t.target as f64 - t.from) * (1.0 - remaining * remaining * remaining)) as! f32
}
fn animation_value(cache: AnimationCache&, id: u64, channel: u64, target: f32,
                   now_ns: i64, options: Transition = Transition {}, reduced: bool = false) -> f32 {
    assert(target == target && target - target == 0.0);
    assert(options.duration_ms >= 0.0 && options.duration_ms <= 86400000.0);
    var slot: i32 = -1;
    for i: i32 in cache.count {
        if cache.tracks[i].id == id && cache.tracks[i].channel == channel { slot = i; break; }
    }
    if slot < 0 {
        // Capacity never changes interaction: an uncached control snaps.
        if cache.count == max_animations { return target; }
        slot = cache.count; cache.count += 1;
        cache.tracks[slot] = AnimationTrack { id: id, channel: channel, from: target, target: target, value: target };
    }
    let t .= cache.tracks[slot]; t.seen = cache.pass;
    t.value = sample_animation(t, now_ns);
    if target != t.target {
        t.from = t.value; t.target = target; t.start_ns = now_ns;
        t.duration_ns = (options.duration_ms as f64 * 1000000.0) as! i64;
    }
    if reduced || options.duration_ms == 0.0 || t.duration_ns <= 0 || now_ns - t.start_ns >= t.duration_ns {
        t.value = target; t.from = target; t.duration_ns = 0;
    } else {
        t.value = sample_animation(t, now_ns);
        if t.value != target { cache.active = true; }
    }
    t.value
}
fn begin_animations(cache: AnimationCache&) { cache.pass += 1; cache.active = false; }
fn finish_animations(cache: AnimationCache&) {
    cache.active = false;
    var count: i32 = 0;
    for i: i32 in cache.count {
        if cache.tracks[i].seen == cache.pass {
            cache.tracks[count] = cache.tracks[i];
            if cache.tracks[count].duration_ns > 0 && cache.tracks[count].value != cache.tracks[count].target { cache.active = true; }
            count += 1;
        }
    }
    cache.count = count;
}
