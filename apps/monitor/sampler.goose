namespace mygoose;
extern fn mon_sample() -> bool;
extern fn mon_value(field: i32) -> f64;
// GPU fields: 25=usage %, 26=state (-1 unavailable, 0 baseline, 1 valid),
// 27=dedicated bytes, 28=shared bytes, 29=memory state. History series 7.
extern fn mon_set_gpu_active(active: bool);
// Process fields: 2=memory bytes (Windows private working set, Linux RSS),
// 5=CPU/time/commit known, 6=private commit/virtual bytes, 12=memory known,
// 13=GPU busiest-engine %, 14=GPU known, 15=I/O rate known. Sort key 6 selects GPU.
// Inspector I/O fields are read on demand once per snapshot, with their own timestamps.
extern fn mon_process_value(row: i32, field: i32) -> f64;
extern fn mon_process_birth(row: i32) -> u64;
extern fn mon_find_process(pid: i64, birth: u64) -> i32;
extern fn mon_detail_value(row: i32, field: i32) -> f64;
extern fn mon_generation() -> i64;
extern fn mon_write_detail_name(row: i32, out: u8[:]) -> i64;
extern fn mon_write_detail_path(row: i32, out: u8[:]) -> i64;
extern fn mon_write_name(row: i32, out: u8[:]) -> i64;
extern fn mon_write_info(field: i32, out: u8[:]) -> i64;
extern fn mon_query(search: const u8[:], sort: i32, ascending: bool) -> i32;
extern fn mon_history(series: i32, bucket: i32, buckets: i32, span: i32) -> f64;
extern fn mon_history_count() -> i32;
extern fn mon_enable_cores();
extern fn mon_core_count() -> i32;
extern fn mon_core_status() -> i32;
extern fn mon_core_omitted() -> i32;
extern fn mon_core_value(row: i32) -> f64;
extern fn mon_core_write_label(row: i32, out: u8[:]) -> i64;
fn mon_core_label(row: i32) -> u8[..48] {
    var bytes: u8[48] = [0; 48]; let length = mon_core_write_label(row, bytes);
    var result: u8[..48] = []; result.append(bytes[..length]); result
}
extern fn mon_write_format(value: f64, style: i32, out: u8[:]) -> i64;
extern fn mon_close();
extern fn mon_control_process(pid: i64, birth: u64, force: bool) -> i32;
extern fn mon_reveal_file(path: const u8[:]) -> i32;
fn mon_detail_name(row: i32) -> u8[..256] {
    var bytes: u8[256] = [0; 256]; let n = mon_write_detail_name(row, bytes);
    var result: u8[..256] = []; result.append(bytes[..n]); result
}
fn mon_detail_path(row: i32) -> u8[..4096] {
    var bytes: u8[4096] = [0; 4096]; let n = mon_write_detail_path(row, bytes);
    var result: u8[..4096] = []; result.append(bytes[..n]); result
}
fn mon_name(row: i32) -> u8[..256] {
    var bytes: u8[256] = [0; 256]; let n = mon_write_name(row, bytes);
    var result: u8[..256] = []; result.append(bytes[..n]); result
}
fn mon_info(field: i32) -> u8[..256] {
    var bytes: u8[256] = [0; 256]; let n = mon_write_info(field, bytes);
    var result: u8[..256] = []; result.append(bytes[..n]); result
}
fn mon_format(value: f64, style: i32) -> u8[..96] {
    var bytes: u8[96] = [0; 96]; let n = mon_write_format(value, style, bytes);
    var result: u8[..96] = []; result.append(bytes[..n]); result
}
