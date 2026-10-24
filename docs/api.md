# API and examples

Applications own their state. A view borrows that state and a `Context`, builds
ordinary layout/controls, and returns. MyGoose owns the event loop, input
routing, layout and damage detection. Views and painter callbacks are
compile-time function arguments; there is no runtime callback object.

## Choose a runner

| Content | Runner | View arguments | Starting example |
| --- | --- | --- | --- |
| Standard controls | `mygoose::run` | state, context | [counter](../examples/counter.goose) |
| Static vectors | `mygoose_graphics::run` | state, context | [canvas](../examples/canvas.goose) |
| Charts | `mygoose_charts::run` | state, context | [charts](../examples/charts.goose) |
| Uploaded RGBA images | `mygoose_images::run` | state, context | [images](../examples/images.goose) |
| Tweens/springs | `mygoose_motion_app::run` | state, context, motion frame | [motion](../examples/motion.goose) |
| Animated vectors | Motion runner with `mygoose_graphics::paint` | state, context, motion frame | [rich](../examples/rich.goose) |

The static runners share one call shape:

```goose
mygoose::run(state, options, view);
mygoose_graphics::run(state, options, view);
mygoose_charts::run(state, options, view);
mygoose_images::run(state, options, view);
```

Each optional runner includes its own painter. Import the core and the packages
you use at the root of your program. Static vectors need only `mygoose` and
`mygoose_graphics`; using vectors does not require animation packages.

For animation, the motion runner supplies one `Frame` to each logical update:

```goose
mygoose_motion_app::run(state, options, animated_view);
mygoose_motion_app::run(state, options, animated_view, mygoose_graphics::paint);
```

`animated_view(state, context, frame)` updates caller-owned Tween/Spring values.
The runner sleeps when motion settles, unless `options.animate_ms` requests
continuous updates. See [motion and drawing](rich.md) for timing, easing and
reduced motion.

## Automatic control transitions

`toggle` automatically animates its knob and track color over 160 ms. The
Boolean changes immediately; the context owns the visual transition. Existing
calls need no extra application state or motion package. Give each toggle a
stable `CheckOptions.key`, especially when controls move or change labels.

Custom views can use the same context cache:

```goose
let height = mygoose::animate(c, "details-height",
    if state.expanded { 200.0 } else { 0.0 },
    mygoose::Transition { duration_ms: 180.0 });
```

Keys are scoped to the current parent. First appearance starts at the target;
subsequent target changes ease from the current visual value. Reversing a
transition preserves position. Built-in controls use separate cache channels,
so a custom property cannot replace a toggle's transition at the same key.
One timestamp is shared across both builds of a logical frame.

The bounded cache retains up to 128 property tracks while their controls or
`animate` calls are present, including settled tracks. Removed entries are
reclaimed after the build. New entries beyond capacity snap to their targets
without changing interaction or evicting a live entry. The normal runner wakes
only while a transition or scroll is active and stops after its final frame.
Use `WindowOptions.reduced_motion` or `Context.reduced_motion` to snap context
transitions. Caller-owned `Tween`/`Spring` tracks remain available for explicit
playback and simulation through the motion package.

## Layout, identity and input

Use `row` and `column` with trailing blocks. They close their containers on
normal completion. A lexical return that leaves the block bypasses its closing
code; use a conditional or a named child function for early exits. Explicit
begin/end forms remain available for dynamic composition.

Controls borrow mutable values and return whether an edit/activation occurred:
buttons activate, checkbox/toggle/slider/select edit their values, and text
inputs/areas edit caller-owned bounded text. `TextInput.submitted` reports
Enter separately from text changes. Read `ListSelection.has_selection` before
using its item. [Tables and scroll areas](tables.md) explain larger data sets.

Give interactive controls stable `Options.key` values. Keys are scoped to their
parent, so repeated rows can reuse a child key under distinct keyed parents.
Changing labels or sibling positions should not redefine an entity. Virtual
selection uses `ListItem { id, generation }` to distinguish identity from row
position. See [interaction](interaction.md) for focus, capture and cancellation.

A view can rebuild twice while handling one input. Do not increment a simulation
or perform unrelated I/O merely because the view was called. Actions belong in
activation/change branches. Use bounded arrays for model storage and iterate
records directly when values describe one entity.

## Continuous animation and custom loops

For a simple continuously changing view, set `WindowOptions.animate_ms` and
sample a caller-owned `AnimationClock`:

```goose
let elapsed = mygoose::animation_elapsed_ns(state.clock, state.paused);
let seconds = elapsed / 1000000000.0;
```

The clock samples the predicted display-frame time when synchronized and the
monotonic clock otherwise. Duplicate or backward timestamps add no time;
paused updates advance the timestamp without advancing animation. Keep updating
the clock during a pause. The explicit overload
`animation_elapsed_ns(clock, now_ns, paused)` supports deterministic simulation
and tests. The [quotes example](../examples/quotes.goose) demonstrates this
without depending on timer/display event numbers or paint counts.

Custom loops can use `FramePacer`, `send_native`, `build_frame`, `damage` and
`paint`. Call `send_native(context, kind)` after a nonnegative `mg_wait` result.
Builds may consume input before a paint is due; update the damage cache only
for a frame that will be painted. [Platform details](platforms.md) cover frame
pacing and live resize. Most apps should use a runner.

## Combining optional painters

Compose extra-node callbacks with an ordinary function:

```goose
fn paint_extra(c: mygoose::Context&, index: i32) {
    mygoose_graphics::paint_canvas(c, index);
    mygoose_images::paint_image(c, index);
    mygoose_charts::paint_chart(c, index);
}
fn paint_app(c: mygoose::Context&) { mygoose::paint(c, paint_extra); }
// mygoose::run(state, options, view, paint_app);
```

Each callback checks its own leaf kind. Optional renderers share `add_leaf`
for bounded payload/geometry storage and `clip_leaf` for dirty/viewport clipping;
ordinary application views do not need to manipulate scene nodes. Image handles
are explicitly owned: keep them alive through painting and call `destroy` when
finished. Chart sampling/history stays with the application; use
`mygoose_charts::theme_palette(context.theme)` to match control colors.

`find_node(context, key)` returns a matching explicit-key node index or `-1`;
`find(context, key)` asserts existence and returns its laid-out rectangle. These
are useful for headless tests and passive annotations after layout. Keys are
parent-scoped, so a search across the whole tree returns the first match.
Direct scene mutation and native `mg_*` calls are lower-level extension points.
