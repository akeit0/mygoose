import mygoose from "..";
import os;
struct Editor { doc: mygoose::TextDocument = mygoose::TextDocument {}, path: u8[..1024] = "notes.txt", saved: bool = false, failed: bool = false }
fn view(s: Editor&, c: mygoose::Context&) {
    mygoose::column(c, mygoose::Box { fill: true, padding: 20.0, gap: 12.0, align: 3 }) {
        mygoose::row(c, mygoose::Box { gap: 16.0, align: 1 }) {
            mygoose::text(c, "Editor", mygoose::TextOptions { size: 24.0, bold: true });
            mygoose::text(c, s.path, mygoose::TextOptions { color: c.theme.muted });
            let save = mygoose::button(c, "Save", mygoose::ButtonOptions { primary: true, key: "save" });
            if save || (c.event.kind == 5 && c.event.ctrl && c.event.code == 83) {
                s.saved = write_file_atomic(s.path, s.doc.bytes); s.failed = !s.saved;
            }
        };
        if mygoose::text_area(c, s.doc, mygoose::AreaOptions { height: max(64.0, c.height - 130.0), key: "document" }) { s.saved = false; }
        mygoose::text(c, if s.failed { "Save failed" } else { if s.saved { "Saved" } else { "Ctrl+S to save | UTF-8 | 64 KiB document limit" } }, mygoose::TextOptions { color: c.theme.muted });
    };
}
fn main() {
    var s = Editor {}; let arguments = args();
    if arguments.len > 1 { assert(arguments[1].len <= s.path.cap); s.path.clear(); s.path.append(arguments[1]); }
    var data: u8[>..] = [];
    if read_file(s.path, data) {
        var clean: u8[>..] = []; for b in data { if b != '\r' { clean.push(b); } }
        assert(mygoose::insert_text(s.doc, clean)); s.doc.cursor = 0; s.doc.anchor = 0;
    }
    mygoose::run(s, mygoose::WindowOptions { title: "MyGoose Editor", width: 800, height: 600 }, view);
}
