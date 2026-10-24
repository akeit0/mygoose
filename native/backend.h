#ifndef MYGOOSE_BACKEND_H
#define MYGOOSE_BACKEND_H
#include <stdint.h>
#include <stdbool.h>

/* The only native ABI used by the Goose core. UTF-8 byte lengths, logical
   coordinates, 0xRRGGBB colors. Backend state stays private to one OS. */
typedef struct { const uint8_t *data; int64_t len; } mg_string;
typedef struct { uint8_t *data; int64_t len; } mg_bytes;
bool mg_open(mg_string title, int32_t width, int32_t height, bool headless);
void mg_close(void);
int32_t mg_wait(int32_t timeout_ms);
enum { MG_EVENT_FRAME = 15, MG_EVENT_ANIMATION = 16 }; /* 12 remains IME cancellation. */
/* Request UI-animation wakes while any transition or scroll is active.
   Controls sample at frame time; wakes never synthesize input deltas. */
void mg_animation_pending(bool active);
/* Enable a display-paced frame event (15), or disable with fps=0. False means
   unsupported/headless: use timed FramePacer waits instead. Never drives UI
   work on another thread. Display refresh is an upper bound on the request. */
bool mg_display_sync(int32_t fps);
int32_t mg_display_hz(void); /* Current window's maximum refresh, 0 if unknown. */
/* Predicted presentation time for event 15, monotonic clock otherwise.
   For animation sampling only; use mg_clock_ns for measured durations. */
int64_t mg_frame_time_ns(void);
float mg_event_x(void); float mg_event_y(void); float mg_event_delta(void);
/* Precise wheel delta is in logical pixels; otherwise it is wheel detents. */
bool mg_event_scroll_pixels(void);
bool mg_event_scroll_smooth(void); /* Coarse input needing control animation. */
int32_t mg_event_code(void); int32_t mg_event_mods(void);
void mg_cursor(int32_t shape); /* 0=arrow, 1=horizontal resize, 2=text */
bool mg_capture(bool enabled); /* owned pointer capture; headless succeeds */
float mg_width(void); float mg_height(void);
float mg_measure(mg_string text, float size, bool bold);
void mg_paint_begin(float x, float y, float w, float h, uint32_t background);
typedef struct { float x, y, w, h; } mg_rect_region;
typedef struct { const mg_rect_region *data; int64_t len; } mg_regions;
enum { MG_MAX_DAMAGE = 16 };
/* Begins one frame with 1..16 damage rectangles. False means the backend
   clears/clips their bounding rectangle instead; callers must paint its gaps. */
bool mg_paint_regions(mg_regions regions, uint32_t background);
void mg_paint_end(void);
void mg_clip(float x, float y, float w, float h);
void mg_rect(float x, float y, float w, float h, float radius, uint32_t color);
void mg_shadow(float x, float y, float w, float h, float radius, float blur,
               float spread, float dx, float dy, uint32_t color, float opacity);
void mg_text(mg_string text, float x, float y, float size, bool bold, uint32_t color);
bool mg_clipboard_set(mg_string text);
int64_t mg_clipboard_get(mg_bytes out);
void mg_ime_anchor(uint64_t owner, float x, float y, float w, float h, float size);
int64_t mg_ime_read(mg_bytes out, bool result);
int32_t mg_ime_cursor(void); int32_t mg_ime_target_start(void); int32_t mg_ime_target_end(void);
bool mg_dump_requested(void); bool mg_dump(void);
uint64_t mg_pixel_hash(void);
int64_t mg_clock_ns(void); int64_t mg_memory_bytes(void); int64_t mg_storage_bytes(void);
/* CPU consumed by this process (user + kernel), excluding idle waits. */
int64_t mg_cpu_ns(void);
/* Stable renderer identifiers: 1=Direct2D, 2=Cairo/Pango, 3=CoreGraphics/CoreText. 0 is retired. */
int32_t mg_renderer(void);
#endif
