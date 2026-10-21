# Tables, scrolling and compound controls

These are portable library controls, available through `import mygoose`.
The activity monitor uses them for its process table and its CPU, memory and
process inspector pages. No sampler, chart, icon or Windows dependency is
required. Run the standalone example with `python tools/build.py table --run`.

## Table layout

Keep a `TableState` alongside the application's data and sort state. Pass the
currently visible `TableColumn` specifications to `table_header`. Stable IDs
in 0–31 retain widths through hiding/reordering; keys must be stable and unique.
The library handles layout, header interaction and horizontal scrolling. The
application owns filtering, sorting and the actual cell contents. Optional
shared selection works with tables and ordinary lists alike.

```goose
let columns: mygoose::TableColumn[2] = [
    mygoose::TableColumn { id: 0, title: "Name", key: "name",
        minimum: 100.0, flex: true, align: 0, ascending: true },
    mygoose::TableColumn { id: 1, title: "Count", key: "count", width: 100.0 }
];
if mygoose::table_header(c, state.table, columns, width, state.sort, state.ascending) {
    // Reorder application data and reset its vertical list offset if needed.
}
mygoose::table_row(c, state.table) {
    mygoose::text(c, name, mygoose::TextOptions { width: state.table.widths[0] });
    mygoose::text_number(c, count, mygoose::TextOptions { width: state.table.widths[1], align: 2 });
};
mygoose::table_scrollbar(c, state.table);
```

Build each row inside `virtual_list` for a large dataset. The table's state is
independent of row count. `table_row` clips and translates its children with the
same horizontal offset as the header. Use `selectable_list` and `selectable_row`
for whole-row selection; see [`examples/table.goose`](../examples/table.goose).

Dragging a divider resizes only its left column; every subsequent column moves
together and retains its width. Minimum/maximum widths come from each column.
`flex` distributes unused viewport width before the first user adjustment.
After resizing, preferred widths remain explicit across window changes.
Header sort keys default to column IDs; `sort_key` maps to an app's own enum.
`TableOptions` supplies header height, font size, divider spacing, hover color
and scrollbar options. Theme colors supply the defaults.

Tab reaches headers, dividers and the scrollbar. Left/Right resizes a focused
divider in eight-pixel steps; the scrollbar also supports Home/End. Native
pointer capture keeps drags working outside a divider. Blur, resize and removal
cancel active interaction. The library applies `Node.cursor` after layout, so
applications do not need cursor bookkeeping in their event loop.

## Selectable lists and rows

Keep a `ListSelection` alongside a `ScrollState`. A compile-time lookup callback
returns `ListItem { id, generation, disabled }` for any index in the current
filtered/sorted dataset. Keep this lookup free of side effects. IDs
must be unique within a list; zero is valid. Use `generation` for reused IDs,
such as a new process with the same PID. Data stays in the application; selection
has constant storage and the library builds only viewport rows plus overscan.

```goose
fn item_at(index: i64) -> mygoose::ListItem {
    // A named local function may read enclosing application state.
    mygoose::ListItem { id: rows[index].id }
}
let changed = mygoose::selectable_list(c, selection, scroll, rows.len, 28.0,
    mygoose::Box { width: width, height: height }, "rows", item_at) { index, item =>
    let activated = mygoose::selectable_row(c, selection, index, item,
        mygoose::Box { width: width, height: 28.0, clip: true }) { node =>
        // Ordinary text/layout, or table_row(c, table) { ... }.
        mygoose::text(c, rows[index].name);
    };
    if activated { /* Optional row action: click, Enter or Space. */ }
};
if changed && selection.has_selection { /* Read selection.item. */ }
```

The list is one Tab stop. Clicking a row focuses that persistent list owner;
virtualizing the row away does not discard keyboard focus. Up/Down, Home/End
and Page Up/Down select and reveal rows, skipping disabled items. Enter/Space
activate the selected row, and Escape clears selection while the list is
focused. Other controls retain their own keyboard input. `selectable_row`
accepts an optional `ButtonStyle`; hover, selection and keyboard focus use the
same rendering as buttons. Row children should present content, with separate
controls placed outside the row.

Selection follows identity through sorting and refreshes. `selection.index`
is its current data index, or -1 if filtered out or removed. In that case the
identity remains selected, which lets an inspector retain the last observed
data. The application decides when removal should clear it. Filtering back in
restores the index; a different generation never inherits selection.

Call `select_item(selection, item)` for programmatic selection, or
`clear_selection(selection)` to discard it. Programmatic changes and keyboard
navigation reveal the row; a focused selection also follows a changed index.
Wheel scrolling can hide selection without snapping back each frame. To reveal
an unchanged selection explicitly, set `selection.reveal = true` before the
next build. Plain `virtual_list` remains available without selection behavior.

## Scroll areas

`ScrollAreaState` owns the offset and measured content height. The context owns
drag and capture through the [shared interaction lifecycle](interaction.md).
An area clips its children, handles wheel input, clamps offsets when content or
viewport size changes and exposes an interactive vertical scrollbar.

```goose
mygoose::scroll_area(c, state.page,
    mygoose::Box { width: width, height: height },
    mygoose::ScrollAreaOptions { key: "page", gap: 14.0 }) { inner_width =>
    // Build content with inner_width, which excludes the scrollbar gutter.
};
```

`begin_scroll_area` / `end_scroll_area` expose the same behavior for code that
needs the viewport record. Pass matching options to both. A scroll area measures
all its content; use `virtual_list` for many uniform rows. The lower-level
`scrollbar` supports either axis, custom thickness/colors and keyboard steps.
All dimensions and offsets use logical pixels.

## Compound buttons

`button_content(c, box, options) { index => ... }` creates one button containing
ordinary layout, text, icons or charts. Its children participate in automatic
measurement; `Box` controls content geometry and `ButtonStyle` controls visual
states. The callback's index allows app-owned focus metadata. The returned bool
has the same activation/disabled/keyboard rules as `button`. Use the supported
composition API instead of changing `c.parent` in application code.

## Context menus

`open_context_menu(c, owner_id, x, y)` opens a menu for an existing focusable
list/button. Call `context_menu(c, owner_id, items, width)` each build after the
owner is constructed; its result is the activated item index, or -1. Items are
`MenuItem { label, shortcut, disabled, separator }`, with at most 16 entries.
Shortcut text is a label; the application implements the corresponding shortcut.

Menus reuse popup input and detached overlay layout, with a shadow, viewport
clamping and no scroll-parent clipping or per-row storage. Keyboard navigation
skips disabled actions and separators; Escape/Tab, outside clicks, blur or owner
removal dismisses the menu. Context requests arrive as `Event { kind: 14, x, y }`
on right-button release. The app chooses which row/control owns the request.
Native caption exclusion includes the popup's whole panel.

## Validation

Core tests exercise shared drag/capture/focus/cancellation, sparse IDs including 31, resize/suffix movement, retained
widths through hiding/reordering, sorting, 10,000 virtual rows, compound row
selection, both scrollbar axes, keyboard input, light themes and partial/full
repaint equality. Selection tests cover single-stop Tab navigation, paging,
off-screen focus, disabled/empty/filtered rows, reused identities and capture
cancellation during replacement. Monitor integration tests cover filtering, process identity,
inspector/window changes and all existing chart and action behavior.
