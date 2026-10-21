# Optional custom window frame

`mygoose_window` replaces the Windows title bar with a Goose caption and
minimize, maximize/restore and close buttons. It keeps native move/resize,
double-click maximize, right-click system menu, Alt+Space/Alt+F4 and normal
Windows snapping via dragging or keyboard shortcuts. Maximize fits the monitor
work area. The maximize button has a restore glyph while maximized; close has
the familiar red hover. Minimize/maximize/restore use Windows system commands
and native transitions, respecting the user's animation settings. Windows 11's
hover Snap Layout popup is not implemented.

macOS extends the Goose content into a transparent title bar, retaining real
AppKit traffic-light buttons, native window resizing, fullscreen and the
system double-click title-bar preference. Its sidebar can extend to the top
of the window; reserve the first 46 logical pixels for the traffic lights.
No Windows caption glyphs are drawn on a Mac. `Frame.native` identifies a
platform using native window controls; `Frame.custom` reports whether the
integrated override is active. The monitor uses it automatically.

Linux retains its native decorations and buttons.
`Frame.custom` reports whether the custom frame was attached. Unsupported
platforms return false and `controls` adds no duplicate buttons.

Pass `false` as the fourth `attach` argument to keep a standard
system title bar. On macOS, `MYGOOSE_WINDOW_STYLE=standard` also disables the
override; `python3 tools/macos.py monitor --window-style standard --install`
sets that preference in the Finder app bundle. The default is `integrated`.

This module uses the optional graphics package for its three vector glyphs.
Use a painter that includes `mygoose_graphics::paint_canvas`; the monitor's
composite painter demonstrates combining it with images. No frame code, DWM
dependency or per-window frame storage is linked into basic examples.

## Integration

Import `mygoose_window from "path/to/mygoose/extras/window"` and keep a
`mygoose_window::Frame` in your application state. The root also declares the
core and graphics packages used by window controls; motion packages are not
required.

1. Call `prepare()` before `mg_open`. Windows defers showing the window so the
   native title bar never flashes during startup.
2. After opening, call `attach(state.frame, minimum_width, minimum_height)`.
   The defaults are 320×200 logical pixels; the monitor uses 700×480.
3. Build a caption row and insert controls at its right edge:

```goose
mygoose_window::caption(s.frame, c,
    mygoose::Box { width: c.width, height: 34.0, align: 1 }) {
    mygoose::text(c, "My app");
    mygoose::spacer(c);
    mygoose_window::controls(s.frame, c);
};
```

Use `controls_width(state.frame)` when budgeting caption content: it returns
138 logical pixels for Goose window buttons, and zero when native decorations
or macOS traffic lights supply the controls.

4. After each `build_frame`, call `sync(state.frame, c)`. It registers the
   caption's horizontal band for native dragging and excludes visible,
   interactive Goose controls. Hit-testing storage is capped at 32 exclusions;
   overflow safely disables caption dragging rather than swallowing controls.
5. Call `detach(state.frame)` before `mg_close`.

All calls belong on the UI thread. Start with the standard resizable window
style. The optional layer retains `WS_CAPTION` and the resize/minimize/maximize
and system-menu styles so Windows can provide native transitions. It removes
the visible frame through [`WM_NCCALCSIZE`](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)
and handles non-client hit testing.
No animation timer, tween, or new dependency is needed; DWM transitions and
the user's desktop animation preferences are left unchanged.

Caption painting is suppressed separately from window styles. The frame blocks
`WM_NCPAINT` and the themed non-client draw messages, and forwards activation
with the documented [`WM_NCACTIVATE` no-repaint parameter](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-ncactivate).
Window/application activation, title, icon, theme and setting updates
run with synchronous default drawing suppressed; the guard preserves visibility
and does not wrap system commands. Caption/resize cursors also avoid default
non-client painting. Detaching restores the original caption bits and client size.
Frame extension is set on attach and composition changes, rather than being
reapplied on blur; inactive windows keep the same custom frame.
There is no fake maximized state in application data: the icon reads the
actual HWND state, including changes made through the keyboard/system menu.
Clicking empty caption space dismisses control focus, popups and IME preedit
before native dragging or the system menu begins, without deactivating the
window. Search text remains in place. This uses the shared Windows backend's
existing blur/dismiss-focus event; applications need no special handler.
On Windows, headless builds draw the controls but window commands have no effect.

Live resize is handled by the shared Windows backend: `mg_wait` delivers frames
during the native move/resize loop, and pending resize buffers retain opaque
content. It requires no custom-frame API or application-loop changes. See
[Windows live resize](../../docs/platforms.md#windows-live-resize).

On macOS the optional adapter accesses an opaque NSWindow through
`native/macos/window.h` and installs a native mouse hook for caption dragging.
Search/buttons remain Goose controls and are excluded from dragging, with the
same bounded exclusion storage. Detaching restores the original AppKit styles,
title visibility and minimum size. The adapter is a separate Objective-C object;
basic examples retain their standard system title bars. Native tests cover
traffic-light presence, content bounds, minimum size, resize, exclusions,
overflow, close, detach and standard-style opt-out.

`python tools/build.py monitor-test` runs real hidden-HWND tests for frame
geometry, DPI scaling, signed monitor coordinates, all resize edges, caption
exclusions, maximize/restore/minimize/close, double-click behavior and cleanup.
They check animation style retention and caption paint suppression for visible
and hidden styles, with DWM non-client drawing enabled and disabled, before and
after restoring. Native title/icon values and detach behavior are checked too.
Direct2D framebuffer comparisons also cover the Goose controls and monitor
layout. Regression tests hover and click directly on the vector glyphs,
checking that the containing button owns hover, capture, focus and activation.
