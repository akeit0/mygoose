namespace mygoose;
import std;

// Browser-style destination animation: retain velocity when wheel input
// retargets an active curve, and shorten large movements. Design references:
// Chromium cc/animation/scroll_offset_animation_curve.{h,cc} (UpdateTarget,
// kInverseDelta); Firefox layout/generic/ScrollAnimationBezierPhysics.cpp.
// These are mathematical curves, sampled by the controls at frame time.
struct ScrollMotion {
    from: f64 = 0.0, target: f64 = 0.0, value: f64 = 0.0, velocity: f64 = 0.0,
    slope: f64 = 0.0, start_ns: i64 = 0, duration_ns: i64 = 0, active: bool = false
}
fn scroll_bezier(t: f64, a: f64, b: f64) -> f64 {
    let u = 1.0 - t; 3.0 * u * u * t * a + 3.0 * u * t * t * b + t * t * t
}
fn scroll_bezier_derivative(t: f64, a: f64, b: f64) -> f64 {
    let u = 1.0 - t; 3.0 * u * u * a + 6.0 * u * t * (b - a) + 3.0 * t * t * (1.0 - b)
}
fn sample_scroll(m: ScrollMotion&, now_ns: i64) -> f32 {
    if !m.active { return m.value as! f32; }
    if now_ns >= m.start_ns + m.duration_ns {
        m.value = m.target; m.velocity = 0.0; m.active = false; return m.value as! f32;
    }
    if now_ns <= m.start_ns {
        m.value = m.from;
        m.velocity = m.slope * (m.target - m.from) * 1000000000.0 / m.duration_ns;
        return m.value as! f32;
    }
    let progress = max(0.0, (now_ns - m.start_ns) as f64 / m.duration_ns as f64);
    // Invert x(t) with bounded bisection. The x control points are monotone.
    var low: f64 = 0.0; var high: f64 = 1.0;
    for i in 32 {
        let t = (low + high) * 0.5;
        if scroll_bezier(t, 0.42, 0.58) < progress { low = t; } else { high = t; }
    }
    let t = (low + high) * 0.5; let y1 = 0.42 * m.slope;
    m.value = m.from + (m.target - m.from) * scroll_bezier(t, y1, 1.0);
    m.velocity = (m.target - m.from) * scroll_bezier_derivative(t, y1, 1.0)
        / scroll_bezier_derivative(t, 0.42, 0.58) * 1000000000.0 / m.duration_ns;
    m.value as! f32
}
fn target_scroll(m: ScrollMotion&, target: f32, now_ns: i64) {
    sample_scroll(m, now_ns);
    if m.active && abs(m.target - target) < 0.001 { return; }
    let distance = target as f64 - m.value;
    if abs(distance) < 0.001 { m = ScrollMotion { value: target, target: target }; return; }
    if m.velocity * distance < 0.0 { m.velocity = 0.0; }
    var duration = clamp(0.2 - (abs(distance) - 120.0) / 3600.0, 0.1, 0.2);
    // Bound the new duration by velocity so short retargets cannot overshoot.
    if abs(m.velocity) > 0.001 { duration = min(duration, 2.0 * abs(distance / m.velocity)); }
    m.slope = m.velocity * duration / distance;
    m.from = m.value; m.target = target; m.start_ns = now_ns;
    m.duration_ns = max(1, (duration * 1000000000.0) as! i64); m.active = true;
}
