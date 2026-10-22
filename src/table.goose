namespace mygoose;
import .ui;
import .scroll;
import std;

// Stable IDs preserve widths when an app hides or reorders columns. Table
// state never depends on the number of data rows or on their contents.
struct TableColumn {
    id: i32 = 0, title: const u8[:] = "", key: const u8[:] = "",
    width: f32 = 80.0, minimum: f32 = 42.0, maximum: f32 = 4096.0,
    flex: bool = false, align: i32 = 2, sort_key: i32 = -1, ascending: bool = false
}
struct TableState {
    preferred: f32[32] = [0.0; 32], widths: f32[32] = [0.0; 32],
    offset: f32 = 0.0, viewport: f32 = 0.0, content: f32 = 0.0, gap: f32 = 8.0
}
struct TableOptions {
    height: f32 = 25.0, gap: f32 = 8.0, size: f32 = 11.0,
    hover: i64 = -1, scrollbar: ScrollbarOptions = ScrollbarOptions {}
}
fn table_header(c: Context&, state: TableState&, columns: const TableColumn[:], width: f32,
                sort: i32&, ascending: bool&, options: TableOptions = TableOptions {}) -> bool {
    assert(columns.len > 0 && columns.len <= 32 && width > 1.0 && options.gap >= 2.0);
    state.viewport = width; state.gap = options.gap;
    var used: f32 = columns.len * options.gap; var flexible: i32 = 0;
    var seen: u32 = 0;
    for col in columns {
        assert(col.id >= 0 && col.id < 32 && col.minimum > 0.0 && col.maximum >= col.minimum);
        let bit: u32 = 1 << col.id; assert((seen & bit) == 0); seen |= bit;
        state.widths[col.id] = max(col.minimum, min(col.maximum, if state.preferred[col.id] > 0.0 { state.preferred[col.id] } else { col.width }));
        if col.flex && state.preferred[col.id] == 0.0 { flexible += 1; } else { used += state.widths[col.id]; }
    }
    for col in columns { if col.flex && state.preferred[col.id] == 0.0 {
        state.widths[col.id] = clamp((width - used) / max(1, flexible), col.minimum, col.maximum);
    } }
    state.content = columns.len * options.gap;
    for col in columns { state.content += state.widths[col.id]; }
    state.offset = clamp(state.offset, 0.0, max(0.0, state.content - width));
    var changed = false; var resized = false;
    row(c, Box { width: width, height: options.height, clip: true }, "table-header"); c.nodes[c.parent].value = -state.offset;
    for col in columns {
        let sort_key = if col.sort_key >= 0 { col.sort_key } else { col.id };
        let active = sort == sort_key;
        var title: u8[..256] = []; title.append(col.title); if active { title.append(if ascending { " ↑" } else { " ↓" }); }
        var key: u8[..256] = []; key.append("sort-"); key.append(col.key);
        let i = button_node(c, title, ButtonOptions { width: state.widths[col.id], key: key,
            style: ButtonStyle { flat: true, hover: options.hover, color: if active { c.theme.text } else { c.theme.muted }, radius: 4.0, align: col.align } });
        c.nodes[i].box.height = options.height; c.nodes[i].box.padding = if col.align == 0 { 6.0 } else { 0.0 }; c.nodes[i].size = options.size;
        if activated(c, i) { if active { ascending = !ascending; } else { sort = sort_key; ascending = col.ascending; } changed = true; }
        key.clear(); key.append("resize-"); key.append(col.key);
        if column_divider(c, state.widths[col.id], col.minimum, col.maximum,
            DividerOptions { key: key, width: options.gap, height: options.height }) { resized = true; }
    }
    end(c);
    if resized { for col in columns { state.preferred[col.id] = state.widths[col.id]; } }
    state.content = columns.len * options.gap;
    for col in columns { state.content += state.widths[col.id]; }
    changed
}
fn table_row<Cells>(c: Context&, state: TableState&, height: f32 = 28.0) {
    row(c, Box { width: state.viewport, height: height, gap: state.gap, align: 1, clip: true });
    c.nodes[c.parent].value = -state.offset; Cells(); end(c);
}
fn table_scrollbar(c: Context&, state: TableState&, options: TableOptions = TableOptions {}) {
    horizontal_scrollbar(c, state.offset, state.viewport, state.content, options.scrollbar);
}
