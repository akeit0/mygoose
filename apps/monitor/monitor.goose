namespace mygoose;
import mygoose from "../..";
import mygoose_graphics from "../../extras/graphics";
import sampler;
import icons;
import charts;
import mygoose_charts from "../../extras/charts";
import mygoose_images from "../../extras/images";
import mygoose_window from "../../extras/window";
import std;

let monitor_blue: u32 = 0x3794ff;
let monitor_green: u32 = 0x27cf4f;
let monitor_pink: u32 = 0xf7699a;
let monitor_amber: u32 = 0xf5b544;
let monitor_teal: u32 = 0x42d3d0;
let monitor_surface: u32 = 0x202124;
let monitor_caption_gap: f32 = 6.0;
let monitor_caption_inset: f32 = 18.0;
let monitor_range_width: f32 = 150.0;
let monitor_pause_width: f32 = 30.0;
let monitor_toolbar_width: f32 = monitor_range_width + monitor_caption_gap + monitor_pause_width;
let monitor_pages: const u8[:][8] = ["Overview", "Processes", "CPU", "Memory", "GPU", "Disk", "Network", "About this PC"];
extern fn mon_process_icon(row: i32) -> i64;
extern fn mon_detail_icon(row: i32) -> i64;
extern fn mon_icons_close();
extern fn mon_icons_pending() -> bool;
extern fn mon_icons_wait();
fn monitor_app_image(c: Context&, handle: i64, size: f32, key: const u8[:]) {
    if handle > 0 { mygoose_images::image(c, mygoose_images::Image { handle }, size, size, key); }
    else { monitor_icon(c, 11, 0x8eabc9, size); }
}
fn monitor_process_image(c: Context&, row: i32, size: f32 = 18.0) {
    monitor_app_image(c, mon_process_icon(row), size, "process-icon");
}
fn monitor_paint_extra(c: Context&, index: i32) {
    mygoose_graphics::paint_canvas(c, index); mygoose_images::paint_image(c, index);
    mygoose_charts::paint_chart(c, index);
}
fn monitor_paint(c: Context&) { paint(c, monitor_paint_extra); }

struct Monitor {
    page: i32 = 0, range: i32 = 60, paused: bool = false, last_sample: i64 = 0,
    search: TextInput = TextInput {}, scroll: ScrollState = ScrollState {},
    sort: i32 = 2, ascending: bool = false, visible: i32 = 0, selected: i64 = -1, show_inspector: bool = false, inspect_focus: bool = false,
    selected_birth: u64 = 0, selection: ListSelection = ListSelection {},
    selected_name: u8[..256] = [], selected_path: u8[..4096] = [],
    selected_values: f64[16] = [0.0; 16], selected_epoch: i64 = -1, selected_alive: bool = false,
    selected_cpu: f32[60] = [0.0; 60], selected_memory: f32[60] = [0.0; 60],
    selected_head: i32 = 0, selected_count: i32 = 0, copied: bool = false,
    detail_scroll: ScrollAreaState = ScrollAreaState {},
    memory_scroll: ScrollAreaState = ScrollAreaState {}, cpu_scroll: ScrollAreaState = ScrollAreaState {},
    gpu_scroll: ScrollAreaState = ScrollAreaState {},
    table: TableState = TableState {},
    action: i32 = 0, action_result: i32 = 0, terminating: bool = false,
    frame: mygoose_window::Frame = mygoose_window::Frame {}
}
fn monitor_theme() -> Theme {
    var t = Theme {}; t.background = 0x121315; t.surface = monitor_surface;
    t.border = 0x33363c; t.hover = 0x2d3541; t.pressed = 0x253e5c;
    t.accent = monitor_blue; t.text = 0xf2f3f5; t.muted = 0x9299a5; t.font_size = 13.0; t.radius = 8.0; t
}
fn monitor_label(c: Context&, s: const u8[:], color: u32 = 0x9299a5, size: f32 = 12.0, bold: bool = false, width: f32 = 0.0) {
    text(c, s, TextOptions { color: color, size: size, bold: bold, width: width });
}
fn monitor_number(c: Context&, value: f64, style: i32 = 0, size: f32 = 13.0, color: u32 = 0xf2f3f5, width: f32 = 0.0) {
    monitor_label(c, mon_format(value, style), color, size, false, width);
}
fn monitor_button(c: Context&, title: const u8[:], width: f32, selected: bool, key: const u8[:]) -> bool {
    let i = button_node(c, title, ButtonOptions { width: width, key: key, selected: selected,
        style: ButtonStyle { flat: true, hover: 0x38393d, pressed: 0x424449,
            selected: 0x45464a, color: c.theme.muted, selected_color: 0xffffff, radius: 14.0 } });
    let n .= c.nodes[i]; n.box.height = 28.0; n.box.clip = true; n.size = 12.0;
    activated(c, i)
}
fn monitor_icon_button(c: Context&, title: const u8[:], width: f32, selected: bool, key: const u8[:], icon: i32, tint: u32) -> bool {
    let nav = icon < 8;
    button_content(c, Box { width: width, height: 30.0, padding: 5.0, clip: true }, ButtonOptions { key: key, selected: selected,
        style: ButtonStyle { flat: true, background: if nav { -1 } else { 0x28292c }, hover: if selected && nav { 0x0b83df } else { 0x303033 },
            pressed: 0x095fa5, selected: if nav { 0x0078d4 } else { 0x45464a }, selected_color: 0xffffff, radius: if nav { 6.0 } else { 15.0 }, align: 0 } }) { i =>
        let color = if selected { 0xffffff } else { tint };
        if title.len == 0 { monitor_icon(c, icon, color, 20.0); }
        else {
            let foreground = c.nodes[i].color;
            row(c, Box { gap: 7.0, align: 1 }) {
                monitor_icon(c, icon, color, 20.0);
                monitor_label(c, title, foreground, if width < 140.0 { 11.0 } else { 12.0 });
            };
        }
    }
}
fn monitor_graph(c: Context&, series: i32, width: f32, height: f32, color: u32, span: i32, percent: bool = false, second: i32 = -1) {
    let buckets = min(span, clamp(((width - 24.0) / 8.0) as! i32, 12, 180));
    var peak: f32 = if percent { 100.0 } else { 1.0 }; var values: f32[..360] = [];
    for i: i32 in buckets {
        let a = mon_history(series, i, buckets, span) as! f32;
        let b = if second >= 0 { mon_history(second, i, buckets, span) as! f32 } else { -1.0 };
        if !percent { peak = max(peak, max(0.0, a) + max(0.0, b)); }
        values.push(a); values.push(b);
    }
    monitor_chart(c, 0, width, height, color, peak, values, buckets, span);
}
fn monitor_card(s: Monitor&, c: Context&, kind: i32, width: f32) {
    let color = match kind {
        0 => monitor_blue, 1 => monitor_green, 2 => monitor_pink,
        3 => monitor_amber, 4 => monitor_teal, _ => 0xb1b8c6,
    };
    let titles: const u8[:][6] = ["CPU", "Memory", "GPU", "Disk", "Network", "Processes"];
    column(c, Box { width: width, height: 206.0, padding: 18.0, gap: 7.0, background: monitor_surface, radius: 16.0, clip: true }) {
        row(c, Box { gap: 9.0, align: 1 }) {
            monitor_icon(c, if kind < 5 { kind + 2 } else { 1 }, color, 26.0, true);
            monitor_label(c, titles[kind], color, 14.0, true);
        };
        match kind {
            0 => {
                monitor_label(c, "Total processor usage");
                if mon_history_count() == 0 { monitor_label(c, "Measuring…", c.theme.text, 26.0); } else { monitor_number(c, mon_value(0), 3, 30.0); }
                row(c, Box { gap: 16.0 }) { monitor_label(c, "User"); monitor_number(c, mon_value(1), 3, 12.0); monitor_label(c, "System"); monitor_number(c, mon_value(2), 3, 12.0); };
                spacer(c); monitor_graph(c, 0, width - 36.0, 48.0, color, s.range, true);
            },
            1 => {
                row(c, Box { gap: 5.0 }) { monitor_label(c, "In use of"); monitor_number(c, mon_value(4), 1, 12.0, c.theme.muted); };
                monitor_number(c, mon_value(3), 1, 30.0);
                row(c, Box { gap: 8.0 }) { monitor_label(c, "Available"); monitor_number(c, mon_value(5), 1, 12.0); };
                spacer(c); monitor_graph(c, 1, width - 36.0, 48.0, color, s.range, true);
            },
            2 => {
                monitor_label(c, "Busiest engine · all adapters", c.theme.muted, 11.0);
                monitor_gpu_usage(c, 30.0);
                row(c, Box { gap: 8.0 }) {
                    monitor_label(c, "Dedicated", c.theme.muted, 11.0);
                    if mon_value(29) == 1 { monitor_number(c, mon_value(27), 1, 12.0); } else { monitor_label(c, "—"); }
                };
                spacer(c); monitor_graph(c, 7, width - 36.0, 48.0, color, s.range, true);
            },
            3 => {
                row(c, Box { gap: 6.0 }) { monitor_label(c, "Free on"); monitor_label(c, mon_info(3)); };
                monitor_number(c, mon_value(11), 1, 30.0);
                row(c, Box { gap: 10.0 }) { monitor_label(c, "Read"); monitor_number(c, mon_value(9), 2, 12.0); monitor_label(c, "Write"); monitor_number(c, mon_value(10), 2, 12.0); };
                spacer(c); if mon_value(21) > 0 { monitor_graph(c, 2, width - 36.0, 48.0, color, s.range, false, 3); }
                else { monitor_label(c, "Waiting for disk counters", c.theme.muted, 11.0); }
            },
            4 => {
                monitor_label(c, "Downloading");
                if mon_value(22) == 0 { monitor_label(c, "Unavailable", c.theme.muted, 24.0); }
                else { if mon_history_count() == 0 { monitor_label(c, "Measuring…", c.theme.text, 26.0); } else { monitor_number(c, mon_value(13), 2, 30.0); } }
                row(c, Box { gap: 8.0 }) { monitor_label(c, "Uploading"); monitor_number(c, mon_value(14), 2, 12.0); };
                spacer(c); monitor_graph(c, 4, width - 36.0, 48.0, color, s.range, false, 5);
            },
            _ => {
                monitor_label(c, "Running now"); monitor_number(c, mon_value(15), 0, 30.0);
                row(c, Box { gap: 10.0 }) { monitor_label(c, "Threads"); monitor_number(c, mon_value(16), 0, 12.0); };
                spacer(c); monitor_graph(c, 6, width - 36.0, 48.0, color, s.range);
            },
        }
    };
}
fn monitor_top(c: Context&, width: f32, key: i32) {
    let count = mon_query("", key, false);
    column(c, Box { width: width, padding: 18.0, gap: 9.0, background: monitor_surface, radius: 16.0, clip: true }) {
        row(c, Box { gap: 8.0, align: 1 }) {
            monitor_icon(c, if key == 2 { 3 } else { 2 }, if key == 2 { monitor_green } else { monitor_blue }, 24.0, true);
            monitor_label(c, if key == 2 { "Largest processes" } else { "Busiest processes" }, if key == 2 { monitor_green } else { monitor_blue }, 14.0, true);
        };
        for i: i32 in min(5, count) {
            row(c, Box { width: width - 36.0, gap: 10.0, align: 1, clip: true }) {
                monitor_process_image(c, i, 16.0);
                monitor_label(c, mon_name(i), c.theme.text, 12.0, false, max(80.0, width - 168.0));
                if mon_process_value(i, if key == 2 { 12 } else { 5 }) > 0 {
                    monitor_number(c, mon_process_value(i, key), if key == 2 { 1 } else { 3 }, 12.0, c.theme.muted);
                } else { monitor_label(c, "—", c.theme.muted, 12.0); }
            };
        }
    };
}
fn monitor_overview(s: Monitor&, c: Context&, width: f32) {
    let cols: i32 = if width >= 840.0 { 3 } else { 2 };
    let card_width = (width - (cols - 1) * 14.0) / cols;
    // The whole dashboard scrolls at smaller window sizes.
    virtual_list(c, s.scroll, if cols == 3 { 3 } else { 4 }, 220.0, Box { width: width, height: max(180.0, c.height - 120.0) }, "overview-scroll") { index =>
        if index < 6 / cols {
            row(c, Box { width: width, height: 220.0, gap: 14.0 }) {
                for j: i32 in cols { monitor_card(s, c, index as i32 * cols + j, card_width); }
            };
        } else {
            row(c, Box { width: width, height: 202.0, gap: 14.0 }) {
                if cols == 3 {
                    monitor_memory_summary(c, 0, card_width, 206.0);
                    monitor_top(c, card_width, 2); monitor_top(c, card_width, 1);
                } else { monitor_top(c, (width - 14.0) * 0.5, 2); monitor_top(c, (width - 14.0) * 0.5, 1); }
            };
        }
    };
}
fn monitor_select(s: Monitor&, row: i32, inspect: bool = true) {
    s.show_inspector = inspect;
    let pid = mon_process_value(row, 0) as! i64; let birth = mon_process_birth(row);
    select_item(s.selection, ListItem { id: pid as! u64, generation: birth });
    if s.selected != pid || s.selected_birth != birth {
        s.selected = pid; s.selected_birth = birth; s.selected_epoch = -1;
        s.selected_name = mon_name(row); s.selected_path.clear(); s.selected_count = 0; s.selected_head = 0; s.copied = false; s.detail_scroll.offset = 0.0;
        s.action = 0; s.action_result = 0; s.terminating = false;
    }
}
fn monitor_refresh_selection(s: Monitor&) {
    if s.selected < 0 || s.selected_epoch == mon_generation() { return; }
    s.selected_epoch = mon_generation();
    let index = mon_find_process(s.selected, s.selected_birth); s.selected_alive = index >= 0;
    if !s.selected_alive { return; }
    s.selected_name = mon_detail_name(index);
    for i: i32 in 16 { s.selected_values[i] = mon_detail_value(index, i); }
    if s.selected_path.len == 0 { s.selected_path = mon_detail_path(index); }
    if s.selected_values[5] > 0 {
        s.selected_cpu[s.selected_head] = s.selected_values[1] as! f32;
        s.selected_memory[s.selected_head] = if s.selected_values[12] > 0 { s.selected_values[2] as! f32 } else { -1.0 };
        s.selected_head = (s.selected_head + 1) % 60; s.selected_count = min(60, s.selected_count + 1);
    }
}
fn monitor_selection_graph(s: Monitor&, c: Context&, memory: bool, width: f32) {
    let color = if memory { monitor_green } else { monitor_blue };
    var peak: f32 = if memory { 1.0 } else { 100.0 };
    for i: i32 in s.selected_count { peak = max(peak, if memory { s.selected_memory[i] } else { s.selected_cpu[i] }); }
    column(c, Box { width: width, padding: 12.0, gap: 9.0, background: if memory { 0x19291f } else { 0x19232f }, radius: 12.0 }) {
        row(c, Box { width: width - 24.0 }) {
            monitor_label(c, if memory { "Memory" } else { "CPU" }, color, 12.0, true); spacer(c);
            if s.selected_values[if memory { 12 } else { 5 }] > 0 { monitor_number(c, s.selected_values[if memory { 2 } else { 1 }], if memory { 1 } else { 3 }, 12.0); }
            else { monitor_label(c, "—"); }
        };
        let buckets = clamp(((width - 48.0) / 8.0) as! i32, 12, 30);
        var values: f32[..60] = [];
        for i: i32 in buckets {
            var level: f32 = -1.0;
            let begin = i * 60 / buckets - (60 - s.selected_count);
            let stop = (i + 1) * 60 / buckets - (60 - s.selected_count);
            for sample: i32 in begin..stop {
                if sample >= 0 {
                    let slot = (s.selected_head - s.selected_count + sample + 60) % 60;
                    level = max(level, if memory { s.selected_memory[slot] } else { s.selected_cpu[slot] });
                }
            }
            values.push(level); values.push(-1.0);
        }
        monitor_chart(c, 0, width - 24.0, 40.0, color, peak, values, buckets, 60);
    };
}
fn monitor_process_action(s: Monitor&, action: i32) {
    s.action = action;
    s.action_result = if action == 3 { mon_reveal_file(s.selected_path) } else { mon_control_process(s.selected, s.selected_birth, action == 2) };
    if action == 2 && s.action_result > 0 { s.terminating = true; }
}
fn monitor_action_message(s: Monitor&) -> const u8[:] {
    let result = s.action_result;
    if result > 0 {
        return match s.action {
            1 => "Close requested",
            2 => "Force quit requested",
            _ => "File location requested",
        };
    }
    match result {
        -1 => "Process exited or changed",
        -2 => "Access denied",
        -3 => "No window to close",
        -4 => "Cannot verify process identity",
        -5 => "Critical system process",
        -7 => "Not supported on this system",
        -8 => "File manager is still opening",
        -9 => "File location unavailable",
        _ => "Action failed",
    }
}
fn monitor_action_button(c: Context&, label: const u8[:], width: f32, key: const u8[:], disabled: bool, danger: bool = false) -> bool {
    let i = button_node(c, label, ButtonOptions { width: width, disabled: disabled, key: key,
        style: ButtonStyle { background: 0x202124, hover: 0x303135, pressed: 0x41444a,
            color: if danger { 0xff5656 } else { c.theme.text }, radius: 6.0 } });
    c.nodes[i].box.height = 32.0; c.nodes[i].size = 12.0; activated(c, i)
}
fn monitor_process_actions(s: Monitor&, c: Context&, width: f32) {
    let disabled = !s.selected_alive || s.selected_birth == 0 || s.terminating;
    row(c, Box { width: width, gap: 6.0 }, "process-actions") {
        if monitor_action_button(c, "Quit", (width - 52.0) * 0.5, "quit-process", disabled) { monitor_process_action(s, 1); }
        if monitor_action_button(c, "Force Quit", (width - 52.0) * 0.5, "force-quit-process", disabled, true) { monitor_process_action(s, 2); }
        let folder = button_content(c, Box { width: 40.0, height: 32.0, padding: 7.0, align: 1 }, ButtonOptions { disabled: s.selected_path.len == 0, key: "show-process-file",
            style: ButtonStyle { background: 0x202124, hover: 0x303135, pressed: 0x41444a, radius: 6.0 } }) { i =>
            monitor_icon(c, 12, if s.selected_path.len == 0 { c.theme.muted } else { c.theme.text }, 18.0);
        };
        if folder { monitor_process_action(s, 3); }
    };
    if s.action_result != 0 { monitor_label(c, monitor_action_message(s), if s.action_result > 0 { c.theme.muted } else { monitor_amber }, 11.0); }
}
struct MonitorDetail {
    title: const u8[:] = "", field: i32 = 0, format: i32 = 0, known: i32 = -1, rate: i32 = -1
}
fn monitor_inspector(s: Monitor&, c: Context&, width: f32, height: f32) {
    monitor_refresh_selection(s);
    let options = ScrollAreaOptions { key: "process-details", step: 36.0, gap: 10.0, padding: 16.0 };
    let page = begin_scroll_area(c, s.detail_scroll, Box { width: width, height: height, background: 0x1a1b1d, radius: 10.0 }, options);
        let inner = page.width - 32.0;
        row(c, Box { width: inner, gap: 10.0, align: 1 }, "details-header") {
            monitor_app_image(c, mon_detail_icon(mon_find_process(s.selected, s.selected_birth)), 30.0, "detail-icon");
            column(c, Box { width: inner - 72.0, gap: 4.0, clip: true }) {
                monitor_label(c, s.selected_name, c.theme.text, 14.0, true, inner - 72.0);
                row(c, Box { gap: 4.0 }) { monitor_label(c, "PID", c.theme.muted, 11.0); monitor_number(c, s.selected as! f64, 0, 11.0, c.theme.muted); };
            };
            let close = c.count;
            if button(c, "×", ButtonOptions { width: 22.0, key: "close-process", style: ButtonStyle { flat: true, hover: 0x38393d, radius: 5.0 } }) { s.selected = -1; }
            if s.inspect_focus { focus(c, c.nodes[close].id, true); s.inspect_focus = false; }
        };
        monitor_process_actions(s, c, inner);
        monitor_selection_graph(s, c, false, inner); monitor_selection_graph(s, c, true, inner);
        row(c, Box { width: inner, align: 1 }) {
            monitor_label(c, "GPU · busiest engine", monitor_pink, 11.0); spacer(c);
            if s.selected_values[14] > 0 && (!s.selected_alive || mon_value(26) == 1) { monitor_number(c, s.selected_values[13], 3, 12.0); } else { monitor_label(c, "—"); }
        };
        monitor_label(c, "DETAILS", c.theme.muted, 10.0);
        let memory_label = mon_info(5); let private_label = mon_info(4);
        let details: MonitorDetail[6] = [
            MonitorDetail { title: "CPU time", field: 4, format: 4, known: 5 },
            MonitorDetail { title: "Threads", field: 3 },
            MonitorDetail { title: memory_label, field: 2, format: 1, known: 12 },
            MonitorDetail { title: private_label, field: 6, format: 1, known: 5 },
            MonitorDetail { title: "Read I/O", field: 7, format: 1, known: 9, rate: 10 },
            MonitorDetail { title: "Written I/O", field: 8, format: 1, known: 9, rate: 11 },
        ];
        for detail in details {
            row(c, Box { width: inner, gap: 5.0, align: 1 }) {
                monitor_label(c, detail.title, c.theme.muted, 11.0); spacer(c);
                if detail.known < 0 || s.selected_values[detail.known] > 0 {
                    if detail.rate >= 0 {
                        if s.selected_values[15] > 0 { monitor_number(c, s.selected_values[detail.rate], 2, 10.0, c.theme.muted); }
                        else { monitor_label(c, "Measuring…", c.theme.muted, 10.0); }
                    }
                    monitor_number(c, s.selected_values[detail.field], detail.format, 12.0);
                } else { monitor_label(c, "—"); }
            };
        }
        row(c, Box { width: inner, gap: 5.0, align: 1 }) {
            monitor_label(c, "State", c.theme.muted, 11.0); spacer(c);
            monitor_label(c, if s.selected_alive { if s.terminating { "Stopping" } else { "Running" } } else { "Exited" }, if s.selected_alive { c.theme.text } else { monitor_amber }, 12.0);
        };
        row(c, Box { width: inner, align: 1 }, "details-executable") {
            monitor_label(c, "EXECUTABLE", c.theme.muted, 10.0); spacer(c);
            if s.selected_path.len > 0 && button(c, if s.copied { "Copied" } else { "Copy" }, ButtonOptions { width: 52.0, key: "copy-path", style: ButtonStyle { flat: true, hover: 0x38393d, radius: 5.0 } }) { s.copied = mg_clipboard_set(s.selected_path); }
        };
        column(c, Box { width: inner, padding: 9.0, gap: 2.0, background: 0x27282b, radius: 7.0, clip: true }) {
            if s.selected_path.len == 0 { monitor_label(c, "Access restricted", c.theme.muted, 11.0); }
            else {
                var start: i64 = 0;
                while start < s.selected_path.len {
                    var stop = start;
                    while stop < s.selected_path.len {
                        var next = stop + 1;
                        while next < s.selected_path.len && (s.selected_path[next] & 0xc0) == 0x80 { next += 1; }
                        if stop > start && text_width(c, s.selected_path[start..next], 11.0, false) > inner - 18.0 { break; }
                        stop = next;
                    }
                    monitor_label(c, s.selected_path[start..stop], c.theme.muted, 11.0); start = stop;
                }
            }
        };
        monitor_label(c, "History since selection · 60 samples", c.theme.muted, 10.0);
        if !s.selected_alive { monitor_label(c, "Showing the last observed values.", monitor_amber, 11.0); }
    end_scroll_area(c, s.detail_scroll, page, options);
}
fn monitor_cell(c: Context&, value: f64, format: i32, width: f32, color: u32, known: bool = true) {
    let formatted = mon_format(value, format); text(c, if known { formatted } else { "—" }, TextOptions { size: 12.0, color: color, width: width, align: 2 });
}
fn monitor_process_item(index: i64) -> ListItem {
    ListItem { id: mon_process_value(index as i32, 0) as! u64, generation: mon_process_birth(index as i32) }
}
fn monitor_caption_search_width(s: Monitor&, c: Context&, width: f32) -> f32 {
    if s.page != 1 { return 0.0; }
    let title = max(text_width(c, "Processes", 17.0, true), text_width(c, if s.paused { "PAUSED" } else { "LIVE / LOCAL" }, 10.0, true));
    // Insets include the gap before the trailing gutter; the other gaps
    // account for title, spacer, search, toolbar and optional window controls.
    let controls = mygoose_window::controls_width(s.frame);
    let reserved = monitor_caption_inset * 2.0 + monitor_toolbar_width + controls +
        monitor_caption_gap * (if controls > 0.0 { 5.0 } else { 4.0 });
    let input = min(300.0, width - title - reserved);
    if input >= 140.0 { input } else { 0.0 }
}
fn monitor_search_id() -> u64 { hash_text("monitor-process-search", 14695981039346656037) }
fn monitor_clear_search(s: Monitor&, c: Context&) {
    s.search.bytes.clear(); s.search.cursor = 0; s.search.anchor = 0; s.scroll.offset = 0.0;
    cancel_composition(c); c.changed = true;
}
fn monitor_search(s: Monitor&, c: Context&, width: f32) {
    row(c, Box { width: width, height: 36.0, padding: 1.0, radius: 18.0, background: 0x28292c }, "process-search") {
        let shell = c.parent;
        row(c, Box { width: width - 2.0, height: 34.0, radius: 17.0, background: 0x28292c, align: 1 }) {
        column(c, Box { width: 10.0, height: 1.0 }) {};
        monitor_icon(c, 10, c.theme.muted, 16.0);
        let input = c.count;
        if text_input(c, s.search, InputOptions { width: width - 56.0, placeholder: "Search processes or PID", key: "search", flat: true, id: monitor_search_id() }) { s.scroll.offset = 0.0; }
        focus_proxy(c, shell, input);
        let owner = c.nodes[input].id;
        if c.event.kind == 5 && c.event.ctrl && c.event.code == 70 {
            focus(c, owner, true); s.search.anchor = 0; s.search.cursor = s.search.bytes.len; c.changed = true;
        }
        if c.event.kind == 5 && c.event.code == key_escape && c.focus == owner {
            if s.search.bytes.len > 0 { monitor_clear_search(s, c); } else { focus(c, 0, true); }
            c.event = Event {};
        }
        if s.search.bytes.len > 0 || (c.ime.active && c.ime.owner == owner) {
            let clear = button_node(c, "×", ButtonOptions { width: 20.0, key: "clear",
                style: ButtonStyle { flat: true, background: 0x494b50, hover: 0x666970, pressed: 0x383a40, color: 0xc2c5cb, radius: 10.0 } });
            c.nodes[clear].box.height = 20.0; c.nodes[clear].size = 12.0;
            if activated(c, clear) {
                monitor_clear_search(s, c); focus(c, owner);
            }
        } else { column(c, Box { width: 20.0, height: 20.0 }) {}; }
        column(c, Box { width: 8.0, height: 1.0 }) {};
        c.nodes[shell].box.background = if c.focus == owner { c.theme.accent } else { 0x28292c };
        };
    };
}
fn monitor_processes(s: Monitor&, c: Context&, width: f32) {
    if c.event.kind == 5 && c.event.ctrl && c.event.code == 73 && s.selected >= 0 && c.focus != monitor_search_id() {
        c.popup = 0; s.show_inspector = true; s.inspect_focus = true; s.detail_scroll.offset = 0.0; c.changed = true; c.event = Event {};
    }
    let caption_search = monitor_caption_search_width(s, c, width + 48.0) > 0.0;
    if !caption_search {
        row(c, Box { width: width, gap: 8.0, align: 1 }) {
            monitor_number(c, mon_value(15), 0, 11.0, c.theme.muted); monitor_label(c, "processes", c.theme.muted, 11.0); spacer(c);
            monitor_search(s, c, min(300.0, width - 180.0));
        };
    }
    s.visible = mon_query(s.search.bytes, s.sort, s.ascending);
    let viewport = max(100.0, c.height - (if caption_search { 132.0 } else { 180.0 }));
    if c.event.kind == 5 && c.event.code == key_escape && s.selected >= 0 { s.selected = -1; c.changed = true; }
    if s.selected >= 0 { select_item(s.selection, ListItem { id: s.selected as! u64, generation: s.selected_birth }); }
    else { clear_selection(s.selection); }
    let panel = s.selected >= 0 && s.show_inspector && width >= 600.0;
    let inspector_only = s.selected >= 0 && s.show_inspector && !panel;
    let pane_width = width - (if panel { 298.0 } else { 0.0 });
    let scrollable = s.visible * 28.0 > viewport;
    let table_width = pane_width - (if scrollable { 18.0 } else { 0.0 });
    let compact = table_width < 590.0;
    let all_columns: TableColumn[7] = [
        TableColumn { id: 0, title: "Name", key: "Name", minimum: 90.0, maximum: 16384.0, flex: true, align: 0, ascending: true },
        TableColumn { id: 1, title: "CPU", key: "CPU", width: 54.0 },
        TableColumn { id: 6, title: "GPU", key: "GPU", width: 54.0 },
        TableColumn { id: 2, title: "Memory", key: "Memory", width: 86.0, minimum: 64.0 },
        TableColumn { id: 3, title: "Threads", key: "Threads", width: 56.0, minimum: 48.0, sort_key: 4 },
        TableColumn { id: 4, title: "CPU time", key: "CPU time", width: 80.0, minimum: 64.0, sort_key: 3 },
        TableColumn { id: 5, title: "PID", key: "PID", width: 70.0, minimum: 48.0, ascending: true }
    ];
    var columns: TableColumn[..7] = [];
    for col in all_columns { if !compact || col.id < 3 || col.id == 5 || col.id == 6 { columns.push(col); } }
    let table_options = TableOptions { hover: 0x28292c, scrollbar: ScrollbarOptions { key: "process-horizontal" } };
    row(c, Box { width: width, gap: 14.0, align: 0 }, "process-panes") {
        if !inspector_only { column(c, Box { width: pane_width, gap: 3.0 }, "process-table-pane") {
            if table_header(c, s.table, columns, table_width, s.sort, s.ascending, table_options) { s.scroll.offset = 0.0; }
            if s.visible == 0 { monitor_label(c, "No matching processes.", c.theme.muted, 16.0); }
            row(c, Box { width: pane_width, height: viewport, gap: 6.0 }, "process-table-body") {
            var context_row: i32 = -1; var context_x: f32 = 0.0; var context_y: f32 = 0.0;
            let selection_changed = selectable_list(c, s.selection, s.scroll, s.visible as i64, 28.0,
                Box { width: table_width, height: viewport }, "process-list", monitor_process_item) { index, item =>
                let i = index as i32; let pid = mon_process_value(i, 0) as! i64; let known = mon_process_value(i, 5) > 0;
                let selected = s.selection.has_selection && same_item(s.selection.item, item);
                let chosen = selectable_row(c, s.selection, index, item, Box { width: table_width, height: 28.0, clip: true },
                    ButtonStyle { flat: true, background: if index % 2 == 0 { 0x1c1d20 } else { 0x121315 },
                        hover: if selected { 0x0b83df } else { 0x2a2b2e }, pressed: 0x0967ae, selected: 0x0078d4, radius: 5.0 }) { choice =>
                let foreground: u32 = if selected { 0xffffff } else { c.theme.text };
                let muted: u32 = if selected { 0xffffff } else { c.theme.muted };
                table_row(c, s.table) {
                    row(c, Box { width: s.table.widths[0], height: 28.0, gap: 7.0, padding: 5.0, align: 1, clip: true }) {
                        monitor_process_image(c, i, 16.0);
                        monitor_label(c, mon_name(i), foreground, 12.0, false, max(20.0, s.table.widths[0] - 33.0));
                    };
                    monitor_cell(c, mon_process_value(i, 1), 3, s.table.widths[1], if mon_process_value(i, 1) > 0 { foreground } else { muted }, known);
                    monitor_cell(c, mon_process_value(i, 13), 3, s.table.widths[6], if mon_process_value(i, 13) > 0 { foreground } else { muted }, mon_process_value(i, 14) > 0);
                    monitor_cell(c, mon_process_value(i, 2), 1, s.table.widths[2], foreground, mon_process_value(i, 12) > 0);
                    if !compact { monitor_cell(c, mon_process_value(i, 3), 0, s.table.widths[3], muted);
                        monitor_cell(c, mon_process_value(i, 4), 4, s.table.widths[4], muted, known); }
                    monitor_cell(c, pid as! f64, 0, s.table.widths[5], muted);
                };
                if c.event.kind == 14 && c.hot == c.nodes[choice].id {
                    context_row = i; context_x = c.event.x; context_y = c.event.y;
                }
                if c.event.kind == 5 && (c.event.code == 93 || (c.event.shift && c.event.code == 121)) &&
                    c.focus == s.selection.owner && selected {
                    let rect = prior_rect(c, c.nodes[choice].id);
                    context_row = i; context_x = rect.x + 28.0; context_y = rect.y + rect.h;
                }
                }; if chosen { monitor_select(s, i); }
            };
            // Resolve context selection after the list, so its previous index cannot
            // overwrite the hovered target. Opening a menu preserves the inspector.
            if context_row >= 0 {
                monitor_select(s, context_row, s.selected >= 0 && s.show_inspector); monitor_refresh_selection(s);
                open_context_menu(c, s.selection.owner, context_x, context_y);
            } else { if selection_changed && s.selection.has_selection && s.selection.index >= 0 { monitor_select(s, s.selection.index as i32); } }
            if scrollable {
                scrollbar(c, s.scroll.offset, viewport, s.visible * 28.0, true,
                    ScrollbarOptions { key: "process-vertical", step: 28.0, track: 0x121315, thumb: 0x53565c, hover: 0x82868e });
            }
            };
            table_scrollbar(c, s.table, table_options);
            row(c, Box { width: pane_width, gap: 6.0, align: 1 }) {
                monitor_number(c, s.visible as f64, 0, 10.0, c.theme.muted); monitor_label(c, "shown - access restricted: dash", c.theme.muted, 10.0);
                spacer(c); monitor_label(c, "100% = one core", c.theme.muted, 10.0);
            };
            if s.action_result != 0 && !s.show_inspector {
                monitor_label(c, monitor_action_message(s), if s.action_result > 0 { c.theme.muted } else { monitor_amber }, 11.0);
            }
        };
        }
        if panel { monitor_inspector(s, c, 284.0, viewport + 48.0); }
        if inspector_only { monitor_inspector(s, c, width, viewport + 48.0); }
    };
}
fn monitor_process_menu(s: Monitor&, c: Context&) {
    if !c.popup_menu || c.popup == 0 { return; }
    if s.page != 1 || s.selected < 0 { c.popup = 0; return; }
    monitor_refresh_selection(s);
    var quit: u8[..280] = []; quit.append("Quit \""); quit.append(s.selected_name); quit.append("\"");
    var only: u8[..280] = []; only.append("Show Only \""); only.append(s.selected_name); only.append("\"");
    let disabled = !s.selected_alive || s.selected_birth == 0 || s.terminating;
    let items: MenuItem[10] = [
        MenuItem { label: quit, disabled: disabled }, MenuItem { label: "Force Quit", disabled: disabled },
        MenuItem { separator: true }, MenuItem { label: "Inspect", shortcut: "Ctrl+I" },
        MenuItem { label: if s.frame.native { "Show in Finder" } else { if s.frame.custom { "Show in File Explorer" } else { "Show in File Manager" } }, disabled: s.selected_path.len == 0 },
        MenuItem { separator: true }, MenuItem { label: "Copy PID" },
        MenuItem { label: "Copy Path", disabled: s.selected_path.len == 0 }, MenuItem { separator: true }, MenuItem { label: only }
    ];
    let action = context_menu(c, s.selection.owner, items);
    if action == 0 { monitor_process_action(s, 1); }
    if action == 1 { monitor_process_action(s, 2); }
    if action == 3 { s.show_inspector = true; s.inspect_focus = true; s.detail_scroll.offset = 0.0; }
    if action == 4 { monitor_process_action(s, 3); }
    if action == 6 { mg_clipboard_set(mon_format(s.selected as! f64, 0)); }
    if action == 7 { s.copied = mg_clipboard_set(s.selected_path); }
    if action == 9 {
        monitor_clear_search(s, c); s.search.bytes.append(s.selected_name);
        s.search.cursor = s.search.bytes.len; s.search.anchor = s.search.cursor; s.scroll.offset = 0.0;
    }
}
fn monitor_section(c: Context&, title: const u8[:], icon: i32 = 3, color: u32 = monitor_green) {
    row(c, Box { gap: 9.0, align: 1 }) {
        monitor_icon(c, icon, color, 26.0, true); monitor_label(c, title, color, 14.0, true);
    };
}
fn monitor_memory_metric(c: Context&, title: const u8[:], value: f64, width: f32) {
    column(c, Box { width: width, gap: 3.0, justify: 2 }) {
        monitor_label(c, title, c.theme.muted, 12.0); monitor_label(c, mon_format(value, 1), c.theme.text, 14.0, true);
    };
}
fn monitor_memory_summary(c: Context&, kind: i32, width: f32, height: f32 = 222.0) {
    let inner = width - 36.0;
    let physical = (mon_value(3) / max(1.0, mon_value(4))) as! f32;
    let commit = (mon_value(7) / max(1.0, mon_value(8))) as! f32;
    let commit_title = mon_info(6); let commit_used = mon_info(7);
    let commit_limit = mon_info(8); let commit_description = mon_info(9);
    column(c, Box { width: width, height: height, padding: 18.0, gap: 12.0, background: monitor_surface, radius: 18.0, clip: true }) {
        monitor_section(c, if kind == 0 { "Memory by Type" } else { if kind == 1 { commit_title } else { "Available Memory" } },
            if kind == 1 { 2 } else { 3 }, if kind == 0 { monitor_green } else { monitor_teal });
        if kind < 2 {
            row(c, Box { width: inner, gap: 14.0, align: 1 }) {
                monitor_ring(c, 108.0, if height <= 206.0 { 100.0 } else { 108.0 }, if kind == 0 { physical } else { commit }, if kind == 0 { monitor_green } else { monitor_teal });
                column(c, Box { width: inner - 122.0, gap: 12.0 }) {
                    monitor_memory_metric(c, if kind == 0 { "In use" } else { commit_used }, mon_value(if kind == 0 { 3 } else { 7 }), inner - 122.0);
                    monitor_memory_metric(c, if kind == 0 { "Available" } else { commit_limit }, mon_value(if kind == 0 { 5 } else { 8 }), inner - 122.0);
                };
            };
            monitor_label(c, if kind == 0 { "Physical memory · used / available" } else { commit_description }, c.theme.muted, 10.0);
        } else {
            monitor_number(c, mon_value(5), 1, 30.0);
            monitor_bar(c, inner, 1.0 - physical, monitor_teal);
            row(c, Box { width: inner }) { monitor_label(c, "Cached"); spacer(c); monitor_number(c, mon_value(6), 1, 12.0); };
            monitor_label(c, "Available for apps and the system.", c.theme.muted, 11.0);
        }
    };
}
fn monitor_memory_tiles(s: Monitor&, c: Context&, width: f32) {
    let count = min(if width >= 840.0 { 6 } else { 3 }, mon_query("", 2, false)); var total: f64 = 0.0;
    for i: i32 in count { total += mon_process_value(i, 2); }
    column(c, Box { width: width, height: 214.0, padding: 18.0, gap: 12.0, background: monitor_surface, radius: 18.0, clip: true }) {
        row(c, Box { width: width - 36.0, gap: 6.0, align: 1 }) {
            monitor_section(c, "Memory by Process", 0); spacer(c); monitor_number(c, total, 1, 11.0, c.theme.muted); monitor_label(c, "shown", c.theme.muted, 11.0);
        };
        if total <= 0.0 { monitor_label(c, "No readable process memory counters."); }
        else {
            // A minimum label width keeps tiny entries useful; the remaining
            // width is proportional to each process's measured memory.
            let shown = count; let shown_total = total;
            let available = width - 36.0 - max(0, shown - 1) * 5.0;
            let minimum = min(92.0, available / max(1, shown)); let flexible = max(0.0, available - minimum * shown);
            row(c, Box { width: width - 36.0, height: 138.0, gap: 5.0 }) {
                for i: i32 in shown {
                    let tile = minimum + flexible * (mon_process_value(i, 2) / max(1.0, shown_total)) as! f32;
                    let key = mon_format(mon_process_value(i, 0), 0);
                    let clicked = button_content(c, Box { width: tile, height: 138.0, padding: 10.0, clip: true }, ButtonOptions { key: key,
                        style: ButtonStyle { flat: true, background: 0x27282c, hover: 0x33353b, pressed: 0x293d39, radius: 10.0 } }) { node =>
                    column(c, Box { width: max(0.0, tile - 20.0), height: 118.0, gap: 3.0, clip: true }) {
                        monitor_process_image(c, i, 22.0); spacer(c);
                        monitor_label(c, mon_name(i), c.theme.text, 11.0, true, max(0.0, tile - 20.0));
                        if mon_process_value(i, 12) > 0 { monitor_number(c, mon_process_value(i, 2), 1, 11.0, c.theme.muted); }
                        else { monitor_label(c, "—", c.theme.muted, 11.0); }
                    };
                    };
                    if clicked { monitor_select(s, i); s.page = 1; s.search.bytes.clear(); s.scroll.offset = 0.0; c.changed = true; }
                }
            };
        }
    };
}
fn monitor_rank(s: Monitor&, c: Context&, width: f32, field: i32 = 2,
    title: const u8[:] = "Using the Most Memory", key: const u8[:] = "memory-show-all") {
    let cpu = field == 1; let color = if cpu { monitor_blue } else { monitor_green };
    let count = min(8, mon_query("", field, false));
    let columns: i32 = if width >= 840.0 { 2 } else { 1 }; let cell = (width - 36.0 - (columns - 1) * 16.0) / columns;
    let scale = max(100.0, mon_process_value(0, 1));
    column(c, Box { width: width, padding: 18.0, gap: if cpu { 8.0 } else { 10.0 }, background: monitor_surface, radius: 18.0 }) {
        row(c, Box { width: width - 36.0, align: 1 }) {
            monitor_section(c, title, if cpu { 2 } else { 3 }, color); spacer(c);
            if button(c, "Show All ›", ButtonOptions { width: 82.0, key: key,
                style: ButtonStyle { flat: true, hover: 0x30373e, color: color, radius: 8.0 } }) {
                s.page = 1; s.sort = field; s.ascending = false; s.search.bytes.clear(); s.scroll.offset = 0.0; s.selected = -1; c.changed = true;
            }
        };
        if cpu { monitor_label(c, "100% = one logical processor", c.theme.muted, 11.0); }
        for row_index: i32 in (count + columns - 1) / columns {
            row(c, Box { width: width - 36.0, gap: 16.0 }) {
                for col: i32 in columns {
                    let index = row_index * columns + col;
                    if index < count {
                        var row_key: u8[..64] = []; row_key.append(if cpu { "cpu-process-" } else { "memory-process-" }); row_key.append(mon_format(mon_process_value(index, 0), 0));
                        let clicked = button_content(c, Box { width: cell, height: if cpu { 40.0 } else { 30.0 }, padding: 5.0, clip: true }, ButtonOptions { key: row_key,
                            style: ButtonStyle { flat: true, hover: 0x2a2d30, pressed: 0x293d39, radius: 6.0 } }) { node =>
                        column(c, Box { width: cell - 10.0, gap: 4.0 }) {
                            row(c, Box { width: cell - 10.0, gap: 8.0, align: 1 }) {
                                monitor_process_image(c, index, 18.0);
                                monitor_label(c, mon_name(index), c.theme.text, 12.0, false, max(40.0, cell - 140.0)); spacer(c);
                                if mon_process_value(index, if cpu { 5 } else { 12 }) > 0 { monitor_number(c, mon_process_value(index, field), if cpu { 3 } else { 1 }, 12.0); }
                                else { monitor_label(c, "—"); }
                            };
                            if cpu { monitor_bar(c, cell - 10.0, (mon_process_value(index, 1) / scale) as! f32, color, 5.0); }
                        };
                        };
                        if clicked {
                            monitor_select(s, index); s.page = 1; s.sort = field; s.ascending = false;
                            s.search.bytes.clear(); s.scroll.offset = 0.0; c.changed = true;
                        }
                    }
                }
            };
        }
    };
}
fn monitor_memory(s: Monitor&, c: Context&, available: f32) {
    let page = begin_scroll_area(c, s.memory_scroll, Box { width: available, height: max(180.0, c.height - 106.0) }, ScrollAreaOptions { key: "memory-scroll" }); let width = page.width;
        column(c, Box { width: width, height: 334.0, padding: 18.0, gap: 10.0, background: monitor_surface, radius: 18.0, clip: true }) {
            row(c, Box { width: width - 36.0, align: 1 }) {
                monitor_section(c, "Memory"); spacer(c);
                monitor_label(c, "● In use", monitor_green, 11.0); monitor_label(c, "   ● Available", 0x96999f, 11.0);
            };
            row(c, Box { width: width - 36.0, height: 76.0, gap: 16.0, align: 2 }) {
                column(c, Box { width: if width >= 840.0 { 190.0 } else { 150.0 }, gap: 0.0 }) {
                    row(c, Box { gap: 4.0 }) { monitor_label(c, "In use of"); monitor_number(c, mon_value(4), 1, 12.0, c.theme.muted); };
                    monitor_label(c, mon_format(mon_value(3), 1), c.theme.text, if width >= 840.0 { 36.0 } else { 28.0 }, true);
                };
                let metric_width = (width - (if width >= 840.0 { 274.0 } else { 234.0 })) / (if width >= 840.0 { 3.0 } else { 2.0 });
                monitor_memory_metric(c, "Available", mon_value(5), metric_width);
                monitor_memory_metric(c, "Cached", mon_value(6), metric_width);
                if width >= 840.0 { monitor_memory_metric(c, mon_info(7), mon_value(7), metric_width); }
            };
            monitor_bar(c, width - 36.0, (mon_value(3) / max(1.0, mon_value(4))) as! f32, monitor_green);
            monitor_graph(c, 1, width - 36.0, 148.0, monitor_green, s.range, true);
        };
        if width >= 840.0 {
            row(c, Box { width: width, gap: 14.0 }) {
                for kind: i32 in 3 { monitor_memory_summary(c, kind, (width - 28.0) / 3.0); }
            };
        } else { for kind: i32 in 3 { monitor_memory_summary(c, kind, width); } }
        monitor_memory_tiles(s, c, width);
        monitor_rank(s, c, width);
    end_scroll_area(c, s.memory_scroll, page);
}
fn monitor_detail(s: Monitor&, c: Context&, width: f32) {
    let disk = s.page == 5; let series: i32 = if disk { 2 } else { 4 };
    let color = if disk { monitor_amber } else { monitor_teal };
    column(c, Box { width: width, padding: 22.0, gap: 14.0, background: monitor_surface, radius: 18.0, clip: true }) {
        monitor_section(c, monitor_pages[s.page], s.page, color);
        row(c, Box { gap: 14.0, align: 1 }) {
            monitor_label(c, if disk { "Read" } else { "Download" }, color); monitor_number(c, mon_value(if disk { 9 } else { 13 }), 2, 30.0);
            monitor_label(c, if disk { "Write" } else { "Upload" }, 0xe8b04c); monitor_number(c, mon_value(if disk { 10 } else { 14 }), 2, 30.0);
        };
        monitor_graph(c, series, width - 44.0, max(110.0, min(230.0, c.height - 460.0)), color, s.range, false, series + 1);
        monitor_label(c, "Automatic scale · stacked rates · newest sample at right", c.theme.muted, 11.0);
    };
    column(c, Box { width: width, padding: 22.0, gap: 12.0, background: monitor_surface, radius: 18.0 }) {
        if disk {
            monitor_label(c, "System volume", color, 15.0, true); monitor_label(c, mon_info(3));
            row(c, Box { gap: 12.0 }) { monitor_label(c, "Free"); monitor_number(c, mon_value(11), 1); monitor_label(c, "Capacity"); monitor_number(c, mon_value(12), 1); };
            monitor_label(c, "I/O graph combines physical disks. Free space refers to the system volume.");
        } else {
            monitor_label(c, "Active hardware adapters", color, 15.0, true);
            monitor_label(c, "Download and upload rates exclude loopback and tunnel interfaces.");
        }
    };
}
fn monitor_cpu_cores(s: Monitor&, c: Context&, width: f32, viewport: f32, count: i32) {
    let columns = clamp(((width - 28.0) / 130.0) as! i32, 1, 6);
    let rows = (count + columns - 1) / columns;
    let cell = (width - 36.0 - (columns - 1) * 8.0) / columns;
    column(c, Box { width: width, padding: 18.0, gap: 12.0, background: monitor_surface, radius: 18.0 }, "cpu-cores") {
        row(c, Box { width: width - 36.0, gap: 6.0, align: 1 }) {
            monitor_section(c, "Logical Processors", 2, monitor_blue); spacer(c);
            monitor_number(c, count as f64, 0, 11.0, c.theme.muted);

        };
        if count == 0 {
            monitor_label(c, if mon_core_status() < 0 { "Per-processor counters are unavailable." } else { "Waiting for the next CPU sample…" });
        } else {
            // Keep the entire page scrollable, but materialize only visible
            // grid rows plus overscan. Even 128 CPUs fit the core UI arena.
            let row_height: f32 = 44.0;
            let first = clamp((max(0.0, s.cpu_scroll.offset - 406.0) / row_height) as! i32 - 1, 0, rows);
            let last = min(rows, first + (viewport / row_height) as! i32 + 3);
            column(c, Box { width: width - 36.0, height: rows * row_height }) {
                column(c, Box { height: first * row_height }) {};
                for row_index: i32 in first..last {
                    row(c, Box { width: width - 36.0, height: row_height, gap: 8.0 }) {
                        for col: i32 in columns {
                            let index = row_index * columns + col;
                            if index < count {
                                let key = mon_format(index as f64, 0);
                                column(c, Box { width: cell, height: 38.0, padding: 6.0, gap: 4.0, clip: true }, key) {
                                    row(c, Box { width: cell - 12.0, align: 1, justify: 3 }) {
                                        monitor_label(c, mon_core_label(index), c.theme.text, 10.0, true);
                                        let usage = mon_core_value(index);
                                        if usage >= 0 { monitor_number(c, usage, 3, 10.0, monitor_blue); }
                                        else { monitor_label(c, "—", c.theme.muted, 11.0); }
                                    };
                                    monitor_bar(c, cell - 12.0, (max(0.0, mon_core_value(index)) / 100.0) as! f32, monitor_blue, 5.0);
                                };
                            }
                        }
                    };
                }
                column(c, Box { height: (rows - last) * row_height }) {};
            };
            monitor_label(c, "Current usage · 100% = one logical processor.", c.theme.muted, 10.0);
        }
        if mon_core_omitted() > 0 { monitor_label(c, "Some logical processors are omitted (128-processor capacity).", monitor_amber, 11.0); }
    };
}
fn monitor_cpu(s: Monitor&, c: Context&, available: f32, core_count: i32 = -1) {
    mon_enable_cores();
    let page = begin_scroll_area(c, s.cpu_scroll, Box { width: available, height: max(180.0, c.height - 106.0) }, ScrollAreaOptions { key: "cpu-scroll" }); let width = page.width;
    column(c, Box { width: width, height: 334.0, padding: 18.0, gap: 10.0, background: monitor_surface, radius: 18.0, clip: true }) {
        row(c, Box { width: width - 36.0, gap: 5.0, align: 1 }) {
            monitor_section(c, "CPU", 2, monitor_blue); spacer(c);
            monitor_number(c, mon_value(18), 0, 11.0, c.theme.muted); monitor_label(c, "logical processors", c.theme.muted, 11.0);
        };
        monitor_label(c, mon_info(1), c.theme.muted, 12.0, false, width - 36.0);
        row(c, Box { width: width - 36.0, height: 76.0, gap: 16.0, align: 2 }) {
            column(c, Box { width: if width >= 840.0 { 190.0 } else { 150.0 } }) {
                monitor_label(c, "Total usage");
                if mon_history_count() == 0 { monitor_label(c, "Measuring…", c.theme.text, 26.0); }
                else { monitor_label(c, mon_format(mon_value(0), 3), c.theme.text, 36.0, true); }
            };
            let metric = (width - (if width >= 840.0 { 274.0 } else { 234.0 })) / (if width >= 840.0 { 3.0 } else { 2.0 });
            column(c, Box { width: metric, gap: 3.0 }) { monitor_label(c, "User"); monitor_number(c, mon_value(1), 3, 14.0, monitor_blue); };
            column(c, Box { width: metric, gap: 3.0 }) { monitor_label(c, "System"); monitor_number(c, mon_value(2), 3, 14.0, monitor_amber); };
            if width >= 840.0 { column(c, Box { width: metric, gap: 3.0 }) { monitor_label(c, "Idle"); monitor_number(c, max(0.0, 100.0 - mon_value(0)), 3, 14.0); }; }
        };
        monitor_graph(c, 0, width - 36.0, 148.0, monitor_blue, s.range, true);
    };
    if width >= 900.0 {
        let left = (width - 14.0) * 0.62;
        row(c, Box { width: width, gap: 14.0 }) {
            monitor_cpu_cores(s, c, left, page.height, if core_count < 0 { mon_core_count() } else { core_count });
            monitor_rank(s, c, width - left - 14.0, 1, "Top CPU Processes", "cpu-show-all");
        };
    } else {
        monitor_cpu_cores(s, c, width, page.height, if core_count < 0 { mon_core_count() } else { core_count });
        monitor_rank(s, c, width, 1, "Top CPU Processes", "cpu-show-all");
    }
    if mon_value(18) > 64 { monitor_label(c, "Overall CPU covers the calling processor group; per-processor charts use provider instances.", c.theme.muted, 11.0); }
    end_scroll_area(c, s.cpu_scroll, page);
}
fn monitor_about(c: Context&, width: f32) {
    column(c, Box { width: width, padding: 24.0, gap: 18.0, background: monitor_surface, radius: 16.0 }) {
        monitor_label(c, mon_info(0), c.theme.text, 28.0, true); monitor_label(c, mon_info(1), c.theme.text, 16.0);
        monitor_label(c, mon_info(2));
        row(c, Box { gap: 12.0 }) { monitor_label(c, "Logical processors"); monitor_number(c, mon_value(18)); monitor_label(c, "Memory"); monitor_number(c, mon_value(4), 1); };
        row(c, Box { gap: 12.0 }) { monitor_label(c, "Uptime"); monitor_number(c, mon_value(17), 4); monitor_label(c, "Last sample"); monitor_number(c, mon_value(19), 5); };
        divider(c); monitor_label(c, "MyGoose Activity Monitor", monitor_blue, 18.0, true);
        monitor_label(c, "Native counters. One sample per second. No helper service.");
        monitor_label(c, "Fixed 4,096-process capacity and 3,600 history samples. Only visible rows are built.");
        monitor_label(c, "Visual design follows Pulse by EGOIST. Built with Goose + MyGoose.");
    };
}
fn monitor_caption(s: Monitor&, c: Context&, width: f32) {
    let search_width = monitor_caption_search_width(s, c, width);
    let height: f32 = if s.page == 1 { 46.0 } else { 58.0 };
    mygoose_window::caption(s.frame, c, Box { width: width, height: height, gap: monitor_caption_gap }) {
        column(c, Box { width: monitor_caption_inset, height: 1.0 }) {};
        column(c, Box { height: height, gap: 1.0, justify: 1 }) {
            monitor_label(c, if s.page == 7 && s.frame.native { "About This Mac" } else { monitor_pages[s.page] }, c.theme.text, 17.0, true);
            if s.page == 3 && !s.paused {
                row(c, Box { gap: 4.0 }) { monitor_number(c, mon_value(4), 1, 10.0, c.theme.muted); monitor_label(c, "physical memory", c.theme.muted, 10.0); };
            } else { monitor_label(c, if s.paused { "PAUSED" } else { "LIVE / LOCAL" }, if s.paused { monitor_amber } else { monitor_green }, 10.0, true); }
        };
        spacer(c);
        if search_width > 0.0 {
            column(c, Box { height: height, justify: 1 }) { monitor_search(s, c, search_width); };
        }
        row(c, Box { width: monitor_toolbar_width, height: height, gap: monitor_caption_gap, align: 1 }, "monitor-toolbar") {
            let spans: i32[4] = [60, 300, 900, 3600]; let labels: const u8[:][4] = ["1m", "5m", "15m", "1h"];
            row(c, Box { width: monitor_range_width, height: 34.0, padding: 3.0, align: 1, background: 0x28292c, radius: 17.0 }) {
                for i: i32 in 4 { if monitor_button(c, labels[i], 36.0, s.range == spans[i], labels[i]) { s.range = spans[i]; } }
            };
            if monitor_icon_button(c, "", monitor_pause_width, s.paused, "pause", if s.paused { 9 } else { 8 }, c.theme.text) { s.paused = !s.paused; }
        };
        column(c, Box { width: monitor_caption_inset - monitor_caption_gap, height: 1.0 }) {};
        mygoose_window::controls(s.frame, c);
    };
}
fn monitor_gpu_usage(c: Context&, size: f32) {
    if mon_value(26) == 1 { monitor_number(c, mon_value(25), 3, size); }
    else { monitor_label(c, if mon_value(26) == 0 { "Measuring…" } else { "Unavailable" }, c.theme.muted, size); }
}
fn monitor_gpu(s: Monitor&, c: Context&, available: f32) {
    let page = begin_scroll_area(c, s.gpu_scroll, Box { width: available, height: max(180.0, c.height - 106.0) }, ScrollAreaOptions { key: "gpu-scroll" }); let width = page.width;
    column(c, Box { width: width, padding: 18.0, gap: 12.0, background: monitor_surface, radius: 18.0, clip: true }) {
        monitor_section(c, "GPU", 4, monitor_pink);
        monitor_label(c, "Busiest engine · all adapters");
        monitor_gpu_usage(c, 36.0);
        monitor_graph(c, 7, width - 36.0, 148.0, monitor_pink, s.range, true);
        row(c, Box { width: width - 36.0, gap: 16.0 }) {
            if mon_value(29) == 1 {
                monitor_memory_metric(c, "Dedicated memory", mon_value(27), (width - 52.0) * 0.5);
                monitor_memory_metric(c, "Shared memory", mon_value(28), (width - 52.0) * 0.5);
            } else { monitor_label(c, "GPU memory unavailable"); }
        };
        monitor_label(c, if mon_value(26) < 0 { "Requires Windows GPU performance counters." } else { "Memory in use across all adapters" }, c.theme.muted, 11.0);
    };
    end_scroll_area(c, s.gpu_scroll, page);
}
fn monitor_view(s: Monitor&, c: Context&) {
    c.theme = monitor_theme();
    if c.event.kind == 5 && c.event.ctrl && c.event.code == 70 { c.popup = 0; s.page = 1; }
    let sidebar: f32 = if c.width >= 1000.0 { 198.0 } else { 154.0 };
    let width = max(420.0, c.width - sidebar - 48.0);
    row(c, Box { fill: true, align: 3 }) {
        column(c, Box { width: sidebar, padding: 10.0, gap: 4.0, align: 3, background: 0x1d1c1b }) {
            if s.frame.custom && s.frame.native { column(c, Box { height: 36.0 }) {}; }
            else {
                monitor_label(c, "MYGOOSE", 0x747e8d, 11.0, true); monitor_label(c, "Activity Monitor", c.theme.text, 17.0, true);
                column(c, Box { height: 14.0 }) {};
            }
            for i: i32 in 8 {
                if i == 2 { monitor_label(c, "HARDWARE", 0x737a86, 10.0); }
                if i == 7 { spacer(c); }
                if monitor_icon_button(c, if i == 7 && s.frame.native { "About This Mac" } else { monitor_pages[i] }, sidebar - 20.0, s.page == i, monitor_pages[i], i, monitor_icon_color(i)) { s.page = i; s.scroll.offset = 0.0; }
            }
            divider(c); monitor_label(c, mon_info(0), 0xb9bec7, 11.0); monitor_label(c, "1 second sampling", c.theme.muted, 10.0);
        };
        mon_set_gpu_active(s.page == 0 || s.page == 1 || s.page == 4);
        column(c, Box { width: width + 48.0 }) {
            monitor_caption(s, c, width + 48.0);
            row(c, Box { width: width + 48.0, padding: if s.page == 1 { 6.0 } else { 24.0 }, clip: true }) {
            if s.page == 1 { column(c, Box { width: 18.0, height: 1.0 }) {}; }
            column(c, Box { width: width, gap: 14.0 }) {
            if s.page == 0 { monitor_overview(s, c, width); }
            if s.page == 1 { monitor_processes(s, c, width); }
            if s.page == 3 { monitor_memory(s, c, width); }
            if s.page == 2 { monitor_cpu(s, c, width); }
            if s.page == 5 || s.page == 6 { monitor_detail(s, c, width); }
            if s.page == 4 { monitor_gpu(s, c, width); }
            if s.page == 7 { monitor_about(c, width); }
            if mon_value(24) > 0 { monitor_label(c, "Process capacity reached: some rows are omitted.", monitor_amber); }
            };
            };
        };
    };
    // Ranked process links can also change the page while building content.
    monitor_process_menu(s, c);
    mon_set_gpu_active(s.page == 0 || s.page == 1 || s.page == 4);
}
fn monitor_run(s: Monitor&) {
    mygoose_window::prepare();
    assert(mg_open("MyGoose Activity Monitor", 1240, 820, false));
    mygoose_window::attach(s.frame, 700.0, 480.0);
    var c = Context {}; var cache = SceneCache {};
    mon_set_gpu_active(s.page == 0 || s.page == 1 || s.page == 4); mon_sample(); s.last_sample = mg_clock_ns();
    build_frame(c, s, mg_width(), mg_height(), monitor_view); mygoose_window::sync(s.frame, c);
    if mg_dump_requested() { mon_icons_wait(); build_frame(c, s, mg_width(), mg_height(), monitor_view); mygoose_window::sync(s.frame, c); }
    if damage(c, cache) { monitor_paint(c); }
    if mg_dump_requested() { assert(mg_dump()); mon_icons_close(); mon_close(); mygoose_window::detach(s.frame); mg_close(); return; }
    while true {
        let remaining = max(1, 1000 - ((mg_clock_ns() - s.last_sample) / 1000000) as! i32);
        let kind = mg_wait(if mon_icons_pending() { if s.paused { 16 } else { min(16, remaining) } } else { if s.paused { 0 } else { remaining } }); if kind < 0 { break; }
        if !s.paused && mg_clock_ns() - s.last_sample >= 1000000000 { s.last_sample = mg_clock_ns(); mon_sample(); }
        send_native(c, kind);
        build_frame(c, s, mg_width(), mg_height(), monitor_view); mygoose_window::sync(s.frame, c);
        if damage(c, cache) { monitor_paint(c); }
    }
    mon_icons_close(); mon_close(); mygoose_window::detach(s.frame); mg_close();
}
