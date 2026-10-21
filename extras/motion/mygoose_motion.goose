namespace mygoose_motion;
import std;
import math;

// State belongs to the caller: no global track registry or allocation.
struct Frame { now_ns: i64 = 0, active: bool = false, reduced: bool = false }
struct Tween {
    value: f32 = 0.0, from: f32 = 0.0, target: f32 = 0.0,
    start_ns: i64 = 0, duration_ns: i64 = 0, initialized: bool = false
}
struct Spring {
    value: f32 = 0.0, velocity: f32 = 0.0, target: f32 = 0.0,
    last_ns: i64 = 0, initialized: bool = false
}
fn finite(value: f32) -> bool { value == value && value - value == 0.0 }
fn linear(t: f32) -> f32 { t }
fn ease_out(t: f32) -> f32 { let v = 1.0 - t; 1.0 - v * v * v }
fn ease_in_out(t: f32) -> f32 { t * t * (3.0 - 2.0 * t) }
fn sample<Ease>(t: Tween&, now_ns: i64) -> f32 {
    if t.duration_ns <= 0 { return t.target; }
    let progress = clamp((now_ns - t.start_ns) as f64 / t.duration_ns as f64, 0.0, 1.0) as! f32;
    let eased = Ease(progress); assert(finite(eased));
    (t.from as f64 + (t.target as f64 - t.from) * eased) as! f32
}
fn sample(t: Tween&, now_ns: i64) -> f32 { sample(t, now_ns, ease_in_out) }
fn tween(t: Tween&, f: Frame&, target: f32, duration_ms: f32 = 220.0) -> f32 { tween(t, f, target, duration_ms, ease_in_out) }
fn tween<Ease>(t: Tween&, f: Frame&, target: f32, duration_ms: f32 = 220.0) -> f32 {
    assert(finite(target) && finite(duration_ms) && duration_ms >= 0.0 && duration_ms <= 86400000.0);
    if !t.initialized {
        t.initialized = true; t.value = target; t.from = target; t.target = target;
    }
    // Sample the old trajectory before retargeting, keeping position continuous.
    t.value = sample(t, f.now_ns, Ease);
    if target != t.target {
        t.from = t.value; t.target = target; t.start_ns = f.now_ns;
        t.duration_ns = (duration_ms as f64 * 1000000.0) as! i64;
    }
    if f.reduced { t.value = target; t.from = target; t.target = target; t.duration_ns = 0; }
    else { if t.duration_ns == 0 || f.now_ns - t.start_ns >= t.duration_ns { t.value = target; }
    else { t.value = sample(t, f.now_ns, Ease); f.active = true; }
    }
    t.value
}
// Analytic damped spring: stable at any frame rate, including long pauses.
// Retargeting keeps both position and velocity. Critical/under/over damping.
fn spring(t: Spring&, f: Frame&, target: f32, frequency: f32 = 3.0, damping: f32 = 0.7, precision: f32 = 0.001) -> f32 {
    assert(finite(target) && finite(frequency) && finite(damping) && finite(precision));
    assert(frequency > 0.0 && frequency <= 100.0 && damping > 0.0 && damping <= 10.0 && precision > 0.0);
    if !t.initialized { t.initialized = true; t.value = target; t.target = target; t.last_ns = f.now_ns; }
    let dt = max(0.0, (f.now_ns - t.last_ns) as f64 / 1000000000.0);
    let w = frequency as f64 * TAU; let z = damping as f64;
    let displacement = t.value as f64 - t.target; let velocity = t.velocity as f64;
    var x: f64 = displacement; var v: f64 = velocity;
    if dt > 0.0 {
        if abs(z - 1.0) < 0.00001 {
            let e = exp(-w * dt); let b = velocity + w * displacement;
            x = e * (displacement + b * dt); v = e * (velocity - w * b * dt);
        } else { if z < 1.0 {
            let a = z * w; let wd = w * sqrt(1.0 - z * z); let b = (velocity + a * displacement) / wd;
            let e = exp(-a * dt); let s = sin(wd * dt); let c = cos(wd * dt);
            x = e * (displacement * c + b * s);
            v = e * ((b * wd - a * displacement) * c + (-displacement * wd - a * b) * s);
        } else {
            let root = sqrt(z * z - 1.0); let r1 = -w * (z - root); let r2 = -w * (z + root);
            let a = (velocity - r2 * displacement) / (r1 - r2); let b = displacement - a;
            let e1 = exp(r1 * dt); let e2 = exp(r2 * dt);
            x = a * e1 + b * e2; v = r1 * a * e1 + r2 * b * e2;
        } }
    }
    t.value = (t.target as f64 + x) as! f32; t.velocity = v as! f32; t.last_ns = f.now_ns; t.target = target;
    if f.reduced || (abs(t.value - target) <= precision && abs(t.velocity) <= precision * frequency) {
        t.value = target; t.velocity = 0.0;
    } else { f.active = true; }
    t.value
}
