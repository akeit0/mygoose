import mygoose from "../src";
struct List { scroll: mygoose::ScrollState = mygoose::ScrollState {} }
fn view(s: List&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 20.0, gap: 12.0, align: 3 }) {
        mygoose::text(c, "10,000 rows", mygoose::TextOptions { size: 24.0, bold: true });
        mygoose::virtual_list(c, s.scroll, 10000, 32.0,
            mygoose::Box { height: max(32.0, c.height - 100.0), align: 3, background: c.theme.surface }, "rows") { i =>
            mygoose::row(c, mygoose::Box { height: 32.0, padding: 6.0, gap: 12.0 }) {
                mygoose::text(c, "Item", mygoose::TextOptions { color: c.theme.muted });
                mygoose::text_number(c, i + 1);
            };
        };
    };
}
fn main() { var s = List {}; mygoose::run(s, mygoose::WindowOptions { title: "MyGoose List", width: 480, height: 600 }, view); }
