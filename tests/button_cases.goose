import .test_support;
import mygoose from "..";
import std;

struct ButtonState { selected: bool = false, disabled: bool = false, align: i32 = 0, clicks: i32 = 0, black: bool = false }
fn button_view(s: ButtonState&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 20.0, background: if s.black { 0 } else { 0x18222e }, opaque: true }) {
        if mygoose::button(c, "Flat button", mygoose::ButtonOptions { width: 180.0, disabled: s.disabled, key: "flat", selected: s.selected,
            style: mygoose::ButtonStyle { flat: true, hover: 0x334455, pressed: 0x556677, selected: 0x2277cc,
                color: 0xeeeeee, selected_color: 0xffffff, radius: 5.0, align: s.align } }) { s.clicks += 1; }
        mygoose::text(c, "Aligned", mygoose::TextOptions { width: 180.0, align: s.align });
    };
}
fn button_frame(c: mygoose::Context&, cache: mygoose::SceneCache&, s: ButtonState&) {
    mygoose::build_frame(c, s, 400.0, 400.0, button_view);
    test_support::paint_checked(c, cache);
}
fn button_background(c: mygoose::Context&) -> u32 {
    for i: i32 in c.count { if c.nodes[i].kind == 3 { return c.nodes[i].background; } }
    assert(false); 0
}
fn run_button_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    var s = ButtonState {}; mygoose::send(c, mygoose::Event { kind: 1, x: 350.0, y: 350.0 });
    button_frame(c, cache, s); assert(button_background(c) == 0x18222e);
    let left = mygoose::mg_pixel_hash(); s.align = 2; button_frame(c, cache, s); assert(mygoose::mg_pixel_hash() != left);
    s.black = true; button_frame(c, cache, s); assert(button_background(c) == 0);
    mygoose::send(c, mygoose::Event { kind: 1, x: 30.0, y: 30.0 }); button_frame(c, cache, s); assert(button_background(c) == 0x334455);
    mygoose::send(c, mygoose::Event { kind: 2, x: 30.0, y: 30.0 }); button_frame(c, cache, s); assert(button_background(c) == 0x556677 && !c.keyboard_focus);
    mygoose::send(c, mygoose::Event { kind: 3, x: 30.0, y: 30.0 }); button_frame(c, cache, s); assert(s.clicks == 1);
    mygoose::send(c, mygoose::Event { kind: 1, x: 350.0, y: 350.0 }); button_frame(c, cache, s);
    let mouse_focus = mygoose::mg_pixel_hash();
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_tab }); button_frame(c, cache, s);
    assert(c.keyboard_focus && mygoose::mg_pixel_hash() != mouse_focus);
    mygoose::send(c, mygoose::Event { kind: 5, code: mygoose::key_enter }); button_frame(c, cache, s); assert(s.clicks == 2);
    s.selected = true; button_frame(c, cache, s); assert(button_background(c) == 0x2277cc);
    s.disabled = true; button_frame(c, cache, s);
    mygoose::click(c, s, "flat", button_view); assert(s.clicks == 2 && button_background(c) == 0x2277cc);
    print("PASS: flat button inheritance, hover/press/selection, disabled input, keyboard focus, alignment and partial/full pixels");
}
