#include <stdint.h>
#include <stdbool.h>
/* Preserve the native frame until platform-specific custom frames are tested. */
void mg_window_prepare(void) {}
bool mg_window_native_controls(void) { return false; }
bool mg_window_frame(bool enabled, float w, float h) { (void)enabled; (void)w; (void)h; return false; }
int32_t mg_window_state(void) { return 0; }
bool mg_window_command(int32_t command) { (void)command; return false; }
void mg_window_region(int32_t kind, float x, float y, float w, float h) {
    (void)kind; (void)x; (void)y; (void)w; (void)h;
}
