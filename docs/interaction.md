# Shared interaction

Interaction stays in the existing `mygoose` package and `src/ui.goose`. A context
owns one pointer capture, drag origin and focus target. Controls retain their
semantic state: widths, scroll offsets and text selection anchors.

`interaction(c, index)` returns hovered, focused, pressed, held, released,
activated and cancelled flags. `activated(c, index)` uses the same rules and
requests the normal follow-up build for an activation. Disabled controls cannot
activate or retain capture/focus.

Selectable rows delegate keyboard focus to their persistent list container,
while each row retains its own pointer capture and activation target. The list
is one Tab stop, and its selected row displays keyboard focus. Scrolling that
row out of the virtual range leaves list focus intact. See [selectable lists
and rows](tables.md#selectable-lists-and-rows).

## Dragging

`pointer_drag(c, index, initial_value, space)` returns the initial scalar value,
`dx`/`dy` in logical pixels, started/held/released flags, an `update` flag and
cancellation information. Call it once per control in each view construction.

```goose
let drag = mygoose::pointer_drag(c, index, width,
    mygoose::Rect { w: available_width, h: header_height });
if drag.update {
    width = clamp(drag.value + drag.dx, minimum_width, maximum_width);
    c.changed = true;
}
```

`space` describes a stable coordinate domain. It excludes the moving divider
or scrollbar thumb. Changing that domain cancels the original mapping.
Window resize/DPI changes also cancel capture. The final release coordinate
is included even when no final motion event arrives. A release outside the
control finishes the drag but does not activate a button under the pointer.

Buttons, sliders, text inputs/documents, column dividers and both scrollbar
axes use the shared lifecycle. Native capture is implemented with Win32
capture and an X11 pointer grab; AppKit supplies mouse-down-view drag delivery.
Headless tests use the same logical lifecycle without capturing the desktop.

## Focus and cancellation

Use `focus(c, owner_id, keyboard)` for programmatic focus. It validates the
target, updates focus indication, cancels old IME composition and cancels any
incompatible pointer capture. Invalid or disabled targets return false. Tab
and Shift+Tab use the same focus path. Focus restoration in dropdowns and
keyboard process navigation also use it.

`focus_proxy(c, container_index, target_index)` makes a row/column's padding
and decorative children focus a descendant control on pointer press. Call it
after creating the target, on every build. The container is interactive for
hit testing and native caption exclusion, but is not another Tab stop. Nested
interactive children keep their own targets, so a clear button still works
independently. The monitor's rounded search field uses this with a flat input.
Disabled/nonfocusable targets return false and leave the container inactive;
disabling a target during a press cancels its proxy's capture and control focus.
Container/target indices must still be valid, with the target inside the container.

Inputs normally derive identity from their parent and key. A unique nonzero
`InputOptions.id` supplies an explicit identity for inputs that change layout
parents. Keeping that ID stable preserves focus, selection and IME composition
while moving a field between a toolbar and a wrapped row. It overrides the key;
programmatic focus uses that ID directly.

`cancel_pointer(c, reason)` releases only this window's native capture and
prevents a later release from activating a control. `capture_pointer(c, id)`
validates an interactive target and reports native capture failure. Ordinary
widgets get capture automatically on press and need neither call.

Cancellation reasons cover explicit cancellation, blur, native capture loss,
Escape, resize/DPI, disabled/removed controls, focus transfer, replacement by
another press and changed drag geometry. Capture loss, Escape and resize keep
keyboard focus; blur clears it. Cancellation retains the latest applied value.
A custom control can restore its own snapshot when rollback is appropriate.

After layout, reconciliation checks that active and focused controls still
exist and remain enabled. Removal therefore needs no widget-specific cleanup.
Input phases are cleared before a follow-up view build, so an event is not
applied twice. Custom widgets apply drag updates and set `c.changed` when their
state needs another build. Controls should not assign `c.active` or `c.focus`
directly.

## Divider and scrollbar state

Divider and scrollbar calls borrow the application's width or offset. The
context owns pointer capture and drag tracking:

```goose
column_divider(c, width, minimum, maximum, options); // returns width-changed
horizontal_scrollbar(c, offset, viewport_width, content_width, options);
scrollbar(c, offset, viewport_length, content_length, vertical, options);
```

`TableState` holds column widths and scroll offsets; `ScrollAreaState` holds
the offset and measured content height. Use `interaction(c, index)` for
capture and focus styling.

## Mouse wheel scrolling

On Windows, whole mouse-wheel notches update a control's clamped destination.
Scroll areas, virtual lists and text areas sample that destination animation on
every frame, including frames caused by pointer movement or a timer. Repeated
notches preserve the current velocity; large movements finish more quickly.
The curve takes 100–200 ms, shortened further when needed to avoid overshoot.
Reversing direction discards pending travel in the old direction.

The design follows Chromium's [scroll animation and velocity-preserving
retargeting](https://github.com/chromium/chromium/blob/main/cc/animation/scroll_offset_animation_curve.cc)
and Firefox's [destination-based frame sampling](https://github.com/mozilla/gecko-dev/blob/master/gfx/layers/apz/src/GenericScrollAnimation.cpp).
Motion belongs to the control, so moving the pointer cannot discard distance
or move an unfinished gesture to another scroller. A click, keyboard input,
focus loss, resize, control removal or an explicit offset change stops it.
Fractional wheel input and macOS scrolling remain direct.

`Event.scroll_smooth` marks coarse input to animate. Custom loops continue to
pass every native event through `send_native` and build with `build_frame`.
Event 16 requests an animation frame while a scroll is active; it carries no
wheel delta and never moves the pointer. The normal paint cadence still applies
in animated apps. Paused and idle apps can paint these wakes immediately.
Windows uses a high-resolution waitable timer when available, with a regular
timer fallback, and stops requesting wakes when the animation finishes.
