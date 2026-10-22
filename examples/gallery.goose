import mygoose from "..";
struct Gallery {
    name: mygoose::TextInput = mygoose::TextInput {}, notifications: bool = true,
    dark: bool = true, volume: f32 = 40.0, saves: i64 = 0,
    list: mygoose::ScrollState = mygoose::ScrollState {}, region: i64 = 0
}
let regions: const u8[:][5] = ["Europe", "North America", "South America", "Asia Pacific", "Africa"];
fn view(s: Gallery&, c: mygoose::Context&) {
    c.theme = if s.dark { mygoose::Theme {} } else { mygoose::light_theme() };
    mygoose::row(c, mygoose::Box { fill: true, padding: 28.0, gap: 32.0, align: 3 }) {
        mygoose::column(c, mygoose::Box { width: 280.0, gap: 14.0 }) {
            mygoose::text(c, "MyGoose", mygoose::TextOptions { size: 28.0, bold: true });
            mygoose::text(c, "Native UI, written in Goose", mygoose::TextOptions { color: c.theme.muted });
            mygoose::divider(c);
            mygoose::text(c, "YOUR NAME", mygoose::TextOptions { size: 12.0, color: c.theme.muted });
            mygoose::text_input(c, s.name, mygoose::InputOptions { width: 280.0, placeholder: "Type here (Unicode supported)", key: "name" });
            if s.name.bytes.len > 0 { mygoose::text(c, s.name.bytes); }
            mygoose::checkbox(c, "Notifications", s.notifications, mygoose::CheckOptions { key: "notifications" });
            mygoose::toggle(c, "Dark mode", s.dark, mygoose::CheckOptions { key: "dark" });
            mygoose::select(c, regions, s.region, mygoose::SelectOptions { width: 280.0, key: "region" });
            mygoose::text(c, "VOLUME", mygoose::TextOptions { size: 12.0, color: c.theme.muted });
            mygoose::slider(c, s.volume, 0.0, 100.0, mygoose::SliderOptions { width: 280.0, key: "volume" });
            mygoose::progress(c, s.volume / 100.0, 280.0);
            mygoose::spacer(c);
            mygoose::row(c, mygoose::Box { gap: 8.0 }) {
                if mygoose::button(c, "Save", mygoose::ButtonOptions { primary: true, key: "save" }) { s.saves += 1; }
                if mygoose::button(c, "Reset", mygoose::ButtonOptions { key: "reset" }) { s.saves = 0; }
            };
            mygoose::text_number(c, s.saves);
        };
        mygoose::column(c, mygoose::Box { grow: 1.0, gap: 12.0, align: 3 }) {
            mygoose::text(c, "10,000 rows", mygoose::TextOptions { size: 22.0, bold: true });
            mygoose::text(c, "Scroll: only visible rows are built", mygoose::TextOptions { color: c.theme.muted });
            mygoose::virtual_list(c, s.list, 10000, 32.0,
                mygoose::Box { height: 352.0, align: 3, background: c.theme.surface, radius: 8.0, shadow: mygoose::drop_shadow() }, "list") { i =>
                mygoose::row(c, mygoose::Box { height: 32.0, padding: 6.0, gap: 12.0 }) {
                    mygoose::text(c, "ROW", mygoose::TextOptions { color: c.theme.muted, size: 12.0 });
                    mygoose::text_number(c, i + 1);
                };
            };
        };
    };
}
fn main() { var s = Gallery {}; mygoose::run(s, mygoose::WindowOptions { title: "MyGoose Gallery", width: 800, height: 540 }, view); }
