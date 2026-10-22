namespace mygoose;
import mygoose from "../..";
import mygoose_graphics from "../../extras/graphics";

// Original 24-unit outline icons. Coordinates scale with the native UI's DPI.
// 0 overview, 1 processes, 2 CPU, 3 memory, 4 GPU, 5 disk, 6 network,
// 7 computer, 8 pause, 9 resume, 10 search, 11 application.
fn monitor_icon_color(kind: i32) -> u32 {
    match kind {
        2 => 0x3794ff,
        3 => 0x32d583,
        4 => 0xf7699a,
        5 => 0xf5b544,
        6 => 0x42d3d0,
        _ => 0xb1b8c6,
    }
}
fn monitor_icon(c: Context&, kind: i32, color: u32, size: f32 = 22.0, badge: bool = false) {
    mygoose_graphics::canvas(c, size, size, "icon") { p =>
        mygoose_graphics::scale(p, size / 24.0) {
            if badge { mygoose_graphics::rect(p, 0.0, 0.0, 24.0, 24.0, mygoose_graphics::Brush { color: color, opacity: 0.15 }, 6.0); }
            let inset: f32 = if badge { 3.0 } else { 0.0 };
            mygoose_graphics::translate(p, inset, inset) {
                mygoose_graphics::scale(p, if badge { 0.75 } else { 1.0 }) {
                    let stroke = mygoose_graphics::Brush { color: color, width: 1.6 };
                    let solid = mygoose_graphics::Brush { color: color };
                    match kind {
                        0 => {
                            for y in 2 { for x in 2 { mygoose_graphics::rect(p, 4.0 + x * 9.0, 4.0 + y * 9.0, 6.0, 6.0, stroke, 1.3); } }
                        },
                        1 => {
                            for i in 3 {
                                mygoose_graphics::rect(p, 4.0, 5.0 + i * 6.0, 2.5, 2.5, solid, 0.6);
                                mygoose_graphics::line(p, 10.0, 6.25 + i * 6.0, 20.0, 6.25 + i * 6.0, stroke);
                            }
                        },
                        2 => {
                            mygoose_graphics::rect(p, 6.0, 6.0, 12.0, 12.0, stroke, 2.0);
                            mygoose_graphics::rect(p, 9.0, 9.0, 6.0, 6.0, stroke, 0.8);
                            for i in 3 {
                                let v = 8.0 + i * 4.0;
                                mygoose_graphics::line(p, v, 3.0, v, 6.0, stroke); mygoose_graphics::line(p, v, 18.0, v, 21.0, stroke);
                                mygoose_graphics::line(p, 3.0, v, 6.0, v, stroke); mygoose_graphics::line(p, 18.0, v, 21.0, v, stroke);
                            }
                        },
                        3 => {
                            mygoose_graphics::rect(p, 3.0, 6.0, 18.0, 11.0, stroke, 1.5);
                            for i in 3 { mygoose_graphics::rect(p, 6.0 + i * 4.5, 9.0, 2.0, 4.0, solid, 0.5); }
                            for i in 4 { mygoose_graphics::line(p, 6.0 + i * 4.0, 17.0, 6.0 + i * 4.0, 20.0, stroke); }
                        },
                        4 => {
                            mygoose_graphics::rect(p, 4.0, 5.0, 17.0, 12.0, stroke, 2.0);
                            mygoose_graphics::circle(p, 11.0, 11.0, 3.4, stroke);
                            mygoose_graphics::line(p, 11.0, 8.0, 11.0, 14.0, stroke); mygoose_graphics::line(p, 8.0, 11.0, 14.0, 11.0, stroke);
                            mygoose_graphics::line(p, 17.5, 9.0, 18.5, 9.0, stroke); mygoose_graphics::line(p, 17.5, 13.0, 18.5, 13.0, stroke);
                            mygoose_graphics::line(p, 2.0, 4.0, 2.0, 19.0, stroke); mygoose_graphics::line(p, 7.0, 17.0, 7.0, 20.0, stroke);
                        },
                        5 => {
                            var path = mygoose_graphics::Path {};
                            mygoose_graphics::move_to(path, 6.0, 5.0); mygoose_graphics::line_to(path, 18.0, 5.0);
                            mygoose_graphics::line_to(path, 21.0, 14.0); mygoose_graphics::line_to(path, 21.0, 19.0);
                            mygoose_graphics::line_to(path, 3.0, 19.0); mygoose_graphics::line_to(path, 3.0, 14.0);
                            mygoose_graphics::close(path); mygoose_graphics::draw_path(p, path, stroke);
                            mygoose_graphics::line(p, 4.0, 14.0, 20.0, 14.0, stroke); mygoose_graphics::circle(p, 17.0, 16.5, 0.9, solid);
                        },
                        6 => {
                            var path = mygoose_graphics::Path {};
                            mygoose_graphics::move_to(path, 4.0, 8.0); mygoose_graphics::line_to(path, 8.0, 4.0);
                            mygoose_graphics::line_to(path, 12.0, 8.0); mygoose_graphics::move_to(path, 8.0, 4.0);
                            mygoose_graphics::line_to(path, 8.0, 20.0); mygoose_graphics::move_to(path, 12.0, 16.0);
                            mygoose_graphics::line_to(path, 16.0, 20.0); mygoose_graphics::line_to(path, 20.0, 16.0);
                            mygoose_graphics::move_to(path, 16.0, 20.0); mygoose_graphics::line_to(path, 16.0, 4.0);
                            mygoose_graphics::draw_path(p, path, stroke);
                        },
                        7 => {
                            mygoose_graphics::rect(p, 3.0, 4.0, 18.0, 13.0, stroke, 2.0);
                            mygoose_graphics::line(p, 12.0, 17.0, 12.0, 21.0, stroke); mygoose_graphics::line(p, 7.0, 21.0, 17.0, 21.0, stroke);
                            mygoose_graphics::line(p, 4.0, 14.0, 20.0, 14.0, stroke);
                        },
                        8 => {
                            mygoose_graphics::rect(p, 7.0, 5.0, 3.0, 14.0, solid, 1.0); mygoose_graphics::rect(p, 14.0, 5.0, 3.0, 14.0, solid, 1.0);
                        },
                        9 => {
                            var path = mygoose_graphics::Path {};
                            mygoose_graphics::move_to(path, 7.0, 4.0); mygoose_graphics::line_to(path, 20.0, 12.0);
                            mygoose_graphics::line_to(path, 7.0, 20.0); mygoose_graphics::close(path); mygoose_graphics::draw_path(p, path, solid);
                        },
                        10 => {
                            mygoose_graphics::circle(p, 10.0, 10.0, 6.0, stroke); mygoose_graphics::line(p, 14.5, 14.5, 20.0, 20.0, stroke);
                        },
                        11 => {
                            mygoose_graphics::rect(p, 3.0, 4.0, 18.0, 16.0, stroke, 2.5);
                            mygoose_graphics::line(p, 4.0, 9.0, 20.0, 9.0, stroke);
                            mygoose_graphics::rect(p, 6.0, 6.0, 2.0, 1.0, solid, 0.4);
                        },
                        12 => {
                            var path = mygoose_graphics::Path {};
                            mygoose_graphics::move_to(path, 3.0, 6.0); mygoose_graphics::line_to(path, 9.0, 6.0);
                            mygoose_graphics::line_to(path, 11.0, 9.0); mygoose_graphics::line_to(path, 21.0, 9.0);
                            mygoose_graphics::line_to(path, 21.0, 19.0); mygoose_graphics::line_to(path, 3.0, 19.0);
                            mygoose_graphics::close(path); mygoose_graphics::draw_path(p, path, stroke);
                        },
                        _ => {},
                    }
                };
            };
        };
    };
}
