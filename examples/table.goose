import mygoose from "..";
import std;

struct Demo {
    table: mygoose::TableState = mygoose::TableState {}, rows: mygoose::ScrollState = mygoose::ScrollState {},
    sort: i32 = 0, ascending: bool = true, selection: mygoose::ListSelection = mygoose::ListSelection {}, hide: bool = false
}
fn view(s: Demo&, c: mygoose::Context&) {
    let width = c.width - 32.0;
    mygoose::column(c, mygoose::Box { fill: true, padding: 16.0, gap: 8.0 }) {
        mygoose::text(c, "Resizable table", mygoose::TextOptions { size: 22.0, bold: true });
        mygoose::text(c, "Drag dividers; widths survive hiding, sorting and scrolling.");
        mygoose::checkbox(c, "Hide status", s.hide, mygoose::CheckOptions { key: "hide-status" });
        var columns: mygoose::TableColumn[..3] = [
            mygoose::TableColumn { id: 0, title: "Item", key: "item", minimum: 120.0, flex: true, align: 0, ascending: true },
            mygoose::TableColumn { id: 1, title: "Count", key: "count", width: 110.0, minimum: 60.0 }
        ];
        if !s.hide { columns.push(mygoose::TableColumn { id: 2, title: "Status", key: "status", width: 150.0, minimum: 80.0 }); }
        if mygoose::table_header(c, s.table, columns, width, s.sort, s.ascending) { s.rows.offset = 0.0; }
        fn item_at(row: i64) -> mygoose::ListItem {
            mygoose::ListItem { id: (if s.ascending { row } else { 9999 - row }) as u64 }
        }
        mygoose::selectable_list(c, s.selection, s.rows, 10000, 28.0,
            mygoose::Box { width: width, height: max(100.0, c.height - 190.0) }, "rows", item_at) { row, item =>
            let index = item.id as i64;
            mygoose::selectable_row(c, s.selection, row, item, mygoose::Box { width: width, height: 28.0, clip: true }) { button =>
                mygoose::table_row(c, s.table) {
                    mygoose::text_number(c, index, mygoose::TextOptions { width: s.table.widths[0] });
                    mygoose::text_number(c, index * 10, mygoose::TextOptions { width: s.table.widths[1], align: 2 });
                    if !s.hide { mygoose::text(c, "Ready", mygoose::TextOptions { width: s.table.widths[2], align: 2 }); }
                };
            };
        };
        mygoose::table_scrollbar(c, s.table);
        mygoose::text(c, "10,000 rows. Click a row, then use arrows, Home/End or Page Up/Down.");
    };
}
fn main() { var s = Demo {}; mygoose::run(s, mygoose::WindowOptions { title: "MyGoose tables", width: 900, height: 650 }, view); }
