import .test_support;
import mygoose from "..";
import std;

struct ToggleState {
    a: bool = false, b: bool = true, show: bool = true, disabled: bool = false,
    swapped: bool = false, custom: bool = false, custom_target: f32 = 0.0
}
fn toggle_group(s: ToggleState&, c: mygoose::Context&, first: bool) {
    mygoose::column(c, mygoose::Box { gap: 8.0 }, if first { "left" } else { "right" }) {
        if first {
            if s.show { mygoose::toggle(c, "First", s.a, mygoose::CheckOptions { key: "switch", disabled: s.disabled }); }
            if s.custom { mygoose::progress(c, mygoose::animate(c, "switch", s.custom_target), 120.0); }
        } else { mygoose::toggle(c, "Second", s.b, mygoose::CheckOptions { key: "switch" }); }
    };
}
fn toggle_view(s: ToggleState&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 20.0, gap: 12.0 }) {
        toggle_group(s,c,!s.swapped); toggle_group(s,c,s.swapped);
    };
}
fn toggle_node(c: mygoose::Context&, text: const u8[:]) -> i32 {
    for i: i32 in c.count { if c.nodes[i].kind == 5 && mygoose::node_text(c,i) == text { return i; } }
    assert(false); -1
}
fn toggle_frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: ToggleState&, now: i64, width: f32 = 400.0) {
    mygoose::begin(c,width,400.0); c.frame_ns = now; toggle_view(s,c); mygoose::finish(c); mygoose::finish_input(c);
    test_support::paint_checked(c,cache);
}
struct AnimationRebuild { enabled: bool = false, calls: i32 = 0, time: i64 = 0, value: f32 = 0.0 }
fn animation_rebuild_view(s: AnimationRebuild&, c: mygoose::Context&) {
    mygoose::toggle(c,"Rebuild",s.enabled,mygoose::CheckOptions { key: "rebuild" });
    s.calls += 1;
    if s.calls % 2 == 1 {
        s.time = c.frame_ns; s.value = c.nodes[c.count - 1].value; c.changed = true;
    } else { assert(c.frame_ns == s.time && c.nodes[c.count - 1].value == s.value); }
}
fn run_animation_cases() {
    let start: i64 = 1000000000;
    var c = mygoose::Context {}; var cache = mygoose::SceneCache {}; var s = ToggleState {};
    toggle_frame(c,cache,s,start);
    assert(c.nodes[toggle_node(c,"First")].value == 0.0 && c.nodes[toggle_node(c,"Second")].value == 1.0);
    assert(c.animations.count == 2 && !c.animations.active);
    let r = c.nodes[toggle_node(c,"First")].rect;
    mygoose::send(c,mygoose::Event { kind: 2, x: r.x + 10.0, y: r.y + 10.0 }); toggle_frame(c,cache,s,start);
    mygoose::send(c,mygoose::Event { kind: 3, x: r.x + 10.0, y: r.y + 10.0 }); toggle_frame(c,cache,s,start);
    assert(s.a && c.nodes[toggle_node(c,"First")].checked && c.nodes[toggle_node(c,"First")].value == 0.0 && c.animations.active);
    let initial = mygoose::mg_pixel_hash();
    toggle_frame(c,cache,s,start + 40000000);
    let halfway = c.nodes[toggle_node(c,"First")].value;
    assert(halfway > 0.0 && halfway < 1.0 && mygoose::mg_pixel_hash() != initial);
    toggle_frame(c,cache,s,start + 40000000); assert(c.nodes[toggle_node(c,"First")].value == halfway);
    s.a = false; s.b = false; s.swapped = true;
    toggle_frame(c,cache,s,start + 40000000);
    assert(c.nodes[toggle_node(c,"First")].value == halfway && c.nodes[toggle_node(c,"Second")].value == 1.0);
    toggle_frame(c,cache,s,start + 80000000);
    assert(c.nodes[toggle_node(c,"First")].value < halfway && c.nodes[toggle_node(c,"Second")].value < 1.0);
    toggle_frame(c,cache,s,start + 200000000);
    assert(!c.animations.active && c.nodes[toggle_node(c,"First")].value == 0.0 && c.nodes[toggle_node(c,"Second")].value == 0.0);
    assert(!mygoose::damage(c,cache));

    // Multiple properties on the same scoped ID use separate channels.
    s.custom = true; toggle_frame(c,cache,s,start + 210000000);
    assert(c.animations.count == 3);
    s.a = true; s.custom_target = 1.0; toggle_frame(c,cache,s,start + 220000000);
    assert(c.animations.active);
    s.show = false; s.custom = false; toggle_frame(c,cache,s,start + 240000000);
    assert(c.animations.count == 1 && !c.animations.active);
    s.show = true; toggle_frame(c,cache,s,start + 260000000);
    assert(c.nodes[toggle_node(c,"First")].value == 1.0 && !c.animations.active);
    s.disabled = true;
    let disabled = c.nodes[toggle_node(c,"First")].rect;
    mygoose::send(c,mygoose::Event { kind: 2, x: disabled.x + 10.0, y: disabled.y + 10.0 }); toggle_frame(c,cache,s,start + 260000000);
    mygoose::send(c,mygoose::Event { kind: 3, x: disabled.x + 10.0, y: disabled.y + 10.0 }); toggle_frame(c,cache,s,start + 260000000);
    assert(s.a);
    c.reduced_motion = true; s.a = false; s.b = true;
    toggle_frame(c,cache,s,start + 280000000,240.0);
    assert(!c.animations.active && c.nodes[toggle_node(c,"First")].value == 0.0 && c.nodes[toggle_node(c,"Second")].value == 1.0);

    // Capacity exhaustion snaps without evicting another live control.
    var bounded = mygoose::AnimationCache {};
    mygoose::begin_animations(bounded);
    for i: i32 in mygoose::max_animations { assert(mygoose::animation_value(bounded,i as u64,0,0.0,start) == 0.0); }
    assert(mygoose::animation_value(bounded,9999,0,1.0,start) == 1.0 && bounded.count == mygoose::max_animations);
    mygoose::begin_animations(bounded); mygoose::finish_animations(bounded); assert(bounded.count == 0 && !bounded.active);
    mygoose::begin_animations(bounded);
    mygoose::animation_value(bounded,1,0,0.0,start);
    mygoose::animation_value(bounded,1,0,1.0,start);
    assert(mygoose::animation_value(bounded,1,0,1.0,start + 10000000,mygoose::Transition { duration_ms: 0.0 }) == 1.0);
    mygoose::finish_animations(bounded); assert(!bounded.active);
    var rebuilt = AnimationRebuild {}; var context = mygoose::Context {};
    mygoose::build_frame(context,rebuilt,400.0,400.0,animation_rebuild_view);
    rebuilt.enabled = true;
    mygoose::build_frame(context,rebuilt,400.0,400.0,animation_rebuild_view);
    assert(rebuilt.calls == 4 && context.animations.active);
    rebuilt.enabled = false; context.reduced_motion = true;
    mygoose::build_frame(context,rebuilt,400.0,400.0,animation_rebuild_view);
    assert(!context.animations.active);
    print("PASS: automatic toggle semantics, position/color frames, scoped IDs/reordering, independent channels, reversal, removal/reappearance, reduced motion, bounded cache and partial/full pixels\n");
}
