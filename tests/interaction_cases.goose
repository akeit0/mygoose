import .test_support;
import mygoose from "../src";
import std;

struct InteractionCase {
    value: f32 = 100.0, domain: f32 = 200.0, show: bool = true, disabled: bool = false,
    starts: i32 = 0, ends: i32 = 0, updates: i32 = 0, cancels: i32 = 0, reason: i32 = 0,
    clicks: i32 = 0, peers: i32 = 0, id: u64 = 0, peer: u64 = 0, slider: f32 = 10.0,
    input: mygoose::TextInput = mygoose::TextInput {}
}
fn interaction_view(s: InteractionCase&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { width: 380.0, padding: 10.0, gap: 8.0 }, "interaction") {
        if s.show {
            let i = mygoose::button_node(c, "Drag", mygoose::ButtonOptions { width: 160.0, disabled: s.disabled, key: "drag" });
            s.id = c.nodes[i].id;
            let drag = mygoose::pointer_drag(c, i, s.value, mygoose::Rect { w: s.domain });
            if drag.started { s.starts += 1; }
            if drag.released { s.ends += 1; }
            if drag.update { s.value = drag.value + drag.dx; s.updates += 1; c.changed = true; }
            if drag.cancelled { s.cancels += 1; s.reason = drag.reason; }
            if mygoose::activated(c, i) { s.clicks += 1; }
        }
        let peer = mygoose::button_node(c, "Peer", mygoose::ButtonOptions { width: 160.0, key: "peer" }); s.peer = c.nodes[peer].id;
        if mygoose::activated(c, peer) { s.peers += 1; }
        mygoose::slider(c, s.slider, 0.0, 100.0, mygoose::SliderOptions { width: 200.0, key: "interaction-slider" });
        mygoose::text_input(c, s.input, mygoose::InputOptions { width: 200.0, key: "interaction-input" });
    };
}
fn interaction_frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: InteractionCase&) {
    mygoose::build_frame(c, s, 400.0, 400.0, interaction_view);
    test_support::paint_checked(c, cache);
}
fn interaction_event(c: mygoose::Context&, cache: mygoose::SceneCache&, s: InteractionCase&, e: mygoose::Event) {
    mygoose::send(c, e); interaction_frame(c, cache, s);
}
fn start_drag(c: mygoose::Context&, cache: mygoose::SceneCache&, s: InteractionCase&) {
    let r = mygoose::find(c, "drag");
    interaction_event(c, cache, s, mygoose::Event { kind: 2, x: r.x + 20.0, y: r.y + 15.0 });
    assert(c.active == s.id && c.pointer.drag_owner == s.id && c.focus == s.id);
}
fn run_interaction_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = InteractionCase {}; interaction_frame(c, cache, s);
    start_drag(c, cache, s); assert(s.starts == 1 && s.updates == 1);
    interaction_event(c, cache, s, mygoose::Event { kind: 1, x: 90.0, y: 300.0 }); assert(s.value == 160.0);
    interaction_event(c, cache, s, mygoose::Event { kind: 3, x: 230.0, y: 300.0 });
    assert(s.value == 300.0 && s.ends == 1 && s.updates == 3 && s.clicks == 0 && s.peers == 0);
    assert(c.active == 0 && c.pointer.drag_owner == 0 && c.focus == s.id);
    interaction_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_enter }); assert(s.clicks == 1);
    // Every cancellation keeps the last value and prevents an orphaned release
    // from activating a control. Capture loss and resize retain keyboard focus.
    let cancellations: i32[3] = [7, 8, 13];
    for kind in cancellations {
        start_drag(c, cache, s); let before = s.value; let ends = s.ends;
        interaction_event(c, cache, s, mygoose::Event { kind: kind });
        assert(c.active == 0 && c.pointer.drag_owner == 0 && s.value == before);
        assert(s.reason == (if kind == 7 { mygoose::cancel_blur } else { if kind == 8 { mygoose::cancel_resize } else { mygoose::cancel_capture_lost } }));
        assert(c.focus == (if kind == 7 { 0 } else { s.id }));
        interaction_event(c, cache, s, mygoose::Event { kind: 3, x: 30.0, y: 25.0 }); assert(s.ends == ends && s.clicks == 1);
    }
    start_drag(c, cache, s); let cancelled = s.cancels;
    interaction_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_escape });
    assert(s.reason == mygoose::cancel_escape && s.cancels == cancelled + 1 && c.focus == s.id && c.active == 0);
    start_drag(c, cache, s);
    interaction_event(c, cache, s, mygoose::Event { kind: 5, code: mygoose::key_tab });
    assert(s.reason == mygoose::cancel_focus && c.focus == s.peer && c.active == 0 && c.keyboard_focus);
    start_drag(c, cache, s); assert(mygoose::focus(c, s.peer, true)); interaction_frame(c, cache, s);
    assert(s.reason == mygoose::cancel_focus && c.active == 0 && c.focus == s.peer);
    assert(!mygoose::focus(c, 123456789) && c.focus == s.peer);
    start_drag(c, cache, s); assert(!mygoose::capture_pointer(c, 123456789) && c.active == s.id);
    mygoose::cancel_pointer(c); interaction_frame(c, cache, s);
    assert(s.reason == mygoose::cancel_explicit && c.active == 0 && c.focus == s.id);
    start_drag(c, cache, s); s.domain += 20.0; interaction_frame(c, cache, s);
    assert(s.reason == mygoose::cancel_geometry && c.active == 0);
    start_drag(c, cache, s); mygoose::build_frame(c, s, 420.0, 400.0, interaction_view);
    assert(s.reason == mygoose::cancel_resize && c.active == 0 && c.focus == s.id);
    interaction_frame(c, cache, s);
    start_drag(c, cache, s); s.disabled = true; interaction_frame(c, cache, s);
    assert(s.reason == mygoose::cancel_disabled && c.active == 0 && c.focus == 0);
    assert(!mygoose::focus(c, s.id)); s.disabled = false; interaction_frame(c, cache, s);
    start_drag(c, cache, s); s.disabled = true; let ends = s.ends;
    interaction_event(c, cache, s, mygoose::Event { kind: 3, x: 30.0, y: 25.0 });
    assert(s.reason == mygoose::cancel_disabled && s.ends == ends && s.clicks == 1);
    s.disabled = false; interaction_frame(c, cache, s);
    start_drag(c, cache, s); s.show = false; interaction_frame(c, cache, s);
    assert(c.active == 0 && c.focus == 0 && c.pointer.drag_owner == 0);
    let peer = mygoose::find(c, "peer");
    interaction_event(c, cache, s, mygoose::Event { kind: 3, x: peer.x + 20.0, y: peer.y + 15.0 }); assert(s.peers == 0);
    s.show = true; interaction_frame(c, cache, s); start_drag(c, cache, s);
    let peer_again = mygoose::find(c, "peer");
    interaction_event(c, cache, s, mygoose::Event { kind: 2, x: peer_again.x + 20.0, y: peer_again.y + 15.0 });
    assert(s.reason == mygoose::cancel_replaced && c.active == s.peer && c.focus == s.peer);
    interaction_event(c, cache, s, mygoose::Event { kind: 3, x: peer_again.x + 20.0, y: peer_again.y + 15.0 }); assert(s.peers == 1);
    // Absolute sliders and text selection also consume the final release
    // coordinate, even when the platform sends no last motion event.
    let slider = mygoose::find(c, "interaction-slider");
    interaction_event(c, cache, s, mygoose::Event { kind: 2, x: slider.x + 6.0, y: slider.y + 14.0 });
    interaction_event(c, cache, s, mygoose::Event { kind: 3, x: slider.x + slider.w - 6.0, y: slider.y + 14.0 }); assert(s.slider == 100.0);
    s.input.bytes.append("abcd"); interaction_frame(c, cache, s); let input = mygoose::find(c, "interaction-input");
    interaction_event(c, cache, s, mygoose::Event { kind: 2, x: input.x + 8.0, y: input.y + 16.0 });
    interaction_event(c, cache, s, mygoose::Event { kind: 3, x: input.x + 180.0, y: input.y + 16.0 });
    assert(s.input.anchor == 0 && s.input.cursor == 4);
    run_proxy_cases(c);
    print("PASS: shared interaction phases, captured/final release, cancellation, focus/Tab, disable/removal, replacement, sliders, text selection and damage\n");
}
struct ProxyCase { disabled: bool = true, shell: i32 = 0, target: i32 = 0 }
fn proxy_case_view(s: ProxyCase&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { width: 200.0, padding: 10.0 }, "proxy") {
        s.shell = c.parent;
        s.target = mygoose::button_node(c, "Target", mygoose::ButtonOptions { width: 100.0, disabled: s.disabled });
        assert(mygoose::focus_proxy(c, s.shell, s.target) == !s.disabled);
    };
}
fn run_proxy_cases(c: mygoose::Context&) {
    var s = ProxyCase {};
    mygoose::build_frame(c, s, 400.0, 400.0, proxy_case_view);
    assert(!mygoose::interactive(c.nodes[s.shell]) && c.focus == 0);
    s.disabled = false; mygoose::build_frame(c, s, 400.0, 400.0, proxy_case_view);
    mygoose::send(c, mygoose::Event { kind: 2, x: 4.0, y: 4.0 });
    mygoose::build_frame(c, s, 400.0, 400.0, proxy_case_view);
    assert(c.focus == c.nodes[s.target].id && c.active == c.nodes[s.shell].id);
    s.disabled = true; mygoose::build_frame(c, s, 400.0, 400.0, proxy_case_view);
    assert(c.focus == 0 && c.active == 0);
}
