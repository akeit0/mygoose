/* X11 (including XWayland/WSLg), Cairo and Pango. No GTK widget tree. */
#define _POSIX_C_SOURCE 200809L
#include "../backend.h"
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/cursorfont.h>
#include <cairo/cairo.h>
#include <cairo/cairo-xlib.h>
#include <pango/pangocairo.h>
#include <locale.h>
#include <wchar.h>
#include <poll.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../damage.h"
#include <limits.h>
#include <errno.h>
#define M_PI 3.14159265358979323846

typedef struct { uint64_t hash; PangoLayout *layout; float width; } layout_entry;
static struct {
    Display *display; Window window; Atom close, clipboard, utf8, targets, transfer;
    XIM im; XIC ic;
    Cursor resize_pointer, text_pointer; int pointer_shape;
    cairo_surface_t *surface, *window_surface; cairo_t *cr;
    uint32_t *pixels; int width, height, code, mods, event, click_count;
    float scale, x, y, delta; double dirty[4];
    Time click_time; int click_x, click_y;
    bool headless, closed, clipboard_valid, captured;
    uint8_t clipboard_text[65536]; int clipboard_length;
    layout_entry layouts[64]; unsigned next_layout;
    uint64_t ime_owner; XPoint spot;
    wchar_t preedit[4096]; int preedit_length, preedit_cursor, pending;
    uint8_t ime_text[16384], result[65536]; int ime_length, cursor, result_length;
} mg;

int64_t mg_clock_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (int64_t)t.tv_sec*1000000000+t.tv_nsec; }
int64_t mg_cpu_ns(void) { struct timespec t; return clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t)==0 ? (int64_t)t.tv_sec*1000000000+t.tv_nsec : -1; }
bool mg_dump_requested(void) { const char *s = getenv("MYGOOSE_DUMP"); return s && *s; }
bool mg_capture(bool enabled) {
    if (mg.headless) return true;
    if (!mg.display || !mg.window) return !enabled;
    if (enabled && !mg.captured) {
        mg.captured = XGrabPointer(mg.display, mg.window, False,
            PointerMotionMask | ButtonPressMask | ButtonReleaseMask,
            GrabModeAsync, GrabModeAsync, None, None, CurrentTime) == GrabSuccess;
        return mg.captured;
    }
    if (!enabled && mg.captured) { XUngrabPointer(mg.display, CurrentTime); XFlush(mg.display); mg.captured = false; }
    return true;
}
void mg_cursor(int32_t shape) {
    if (shape < 0 || shape > 2) shape = 0;
    if (mg.headless || !mg.display || !mg.window || mg.pointer_shape == shape) return;
    mg.pointer_shape = shape;
    if (shape == 1) {
        if (!mg.resize_pointer) mg.resize_pointer = XCreateFontCursor(mg.display, XC_sb_h_double_arrow);
        XDefineCursor(mg.display, mg.window, mg.resize_pointer);
    } else if (shape == 2) {
        if (!mg.text_pointer) mg.text_pointer = XCreateFontCursor(mg.display, XC_xterm);
        XDefineCursor(mg.display, mg.window, mg.text_pointer);
    } else XUndefineCursor(mg.display, mg.window);
    XFlush(mg.display);
}
static void color(uint32_t c, double alpha) { cairo_set_source_rgba(mg.cr, ((c>>16)&255)/255.0, ((c>>8)&255)/255.0, (c&255)/255.0, alpha); }
static void buffer(int w, int h) {
    if (w == mg.width && h == mg.height && mg.surface) return;
    if (w < 1 || h < 1 || w > 16384 || h > 16384 || (int64_t)w*h > 67108864) {
        fputs("MyGoose: invalid framebuffer size\n", stderr); exit(1);
    }
    if (mg.cr) cairo_destroy(mg.cr);
    if (mg.surface) cairo_surface_destroy(mg.surface);
    mg.surface = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    if (cairo_surface_status(mg.surface) != CAIRO_STATUS_SUCCESS) { fputs("MyGoose: cannot allocate framebuffer\n", stderr); exit(1); }
    mg.cr = cairo_create(mg.surface); cairo_scale(mg.cr, mg.scale, mg.scale);
    mg.pixels = (uint32_t *)cairo_image_surface_get_data(mg.surface); mg.width = w; mg.height = h;
    if (mg.window_surface) cairo_xlib_surface_set_size(mg.window_surface, w, h);
}
static PangoLayout *layout(mg_string text, float size, bool bold, float *width) {
    uint64_t hash = 14695981039346656037ULL;
    for (int64_t i=0; i<text.len; i++) hash = (hash^text.data[i])*1099511628211ULL;
    uint32_t bits; memcpy(&bits, &size, sizeof(bits)); hash = (hash^bits)*1099511628211ULL ^ bold;
    for (int i=0; i<64; i++) if (mg.layouts[i].layout && mg.layouts[i].hash == hash) {
        *width = mg.layouts[i].width; return mg.layouts[i].layout;
    }
    layout_entry *entry = &mg.layouts[mg.next_layout++%64];
    if (entry->layout) g_object_unref(entry->layout);
    PangoLayout *p = pango_cairo_create_layout(mg.cr);
    PangoFontDescription *font = pango_font_description_new();
    pango_font_description_set_family(font, "sans"); pango_font_description_set_absolute_size(font, size*PANGO_SCALE);
    pango_font_description_set_weight(font, bold ? PANGO_WEIGHT_SEMIBOLD : PANGO_WEIGHT_NORMAL);
    pango_layout_set_font_description(p, font); pango_font_description_free(font);
    pango_layout_set_single_paragraph_mode(p, TRUE); pango_layout_set_text(p, (const char *)text.data, (int)text.len);
    int w; pango_layout_get_size(p, &w, NULL); *width = (float)w/PANGO_SCALE;
    *entry = (layout_entry){hash, p, *width}; return p;
}
static void present(bool full) {
    if (!mg.window_surface) return;
    cairo_t *cr = cairo_create(mg.window_surface);
    if (!full) { cairo_rectangle(cr,mg.dirty[0]*mg.scale,mg.dirty[1]*mg.scale,mg.dirty[2]*mg.scale,mg.dirty[3]*mg.scale); cairo_clip(cr); }
    cairo_set_source_surface(cr, mg.surface, 0, 0); cairo_paint(cr); cairo_destroy(cr);
    cairo_surface_flush(mg.window_surface); XFlush(mg.display);
}
static void preedit_encode(void) {
    mbstate_t state = {0}; mg.ime_length = mg.cursor = 0;
    for (int i=0; i<mg.preedit_length; i++) {
        char bytes[MB_LEN_MAX]; size_t n = wcrtomb(bytes, mg.preedit[i], &state);
        if (n == (size_t)-1 || n > sizeof(mg.ime_text)-(size_t)mg.ime_length) break;
        memcpy(mg.ime_text+mg.ime_length, bytes, n); mg.ime_length += (int)n;
        if (i < mg.preedit_cursor) mg.cursor = mg.ime_length;
    }
    mg.pending = 10;
}
static int preedit_start(XIC ic, XPointer client, XPointer call) {
    (void)ic; (void)client; (void)call; mg.preedit_length = mg.preedit_cursor = 0; preedit_encode(); return 4096;
}
static void preedit_done(XIC ic, XPointer client, XPointer call) {
    (void)ic; (void)client; (void)call; mg.preedit_length = mg.ime_length = 0; mg.pending = 12;
}
static void preedit_draw(XIC ic, XPointer client, XPointer call) {
    (void)ic; (void)client; XIMPreeditDrawCallbackStruct *draw = (void *)call;
    int first = draw->chg_first, count = draw->chg_length;
    if (first < 0 || count < 0 || first > mg.preedit_length || count > mg.preedit_length-first) return;
    wchar_t value[4096]; int n = 0;
    if (draw->text) {
        XIMText *text = draw->text;
        if (text->length > 4096) return;
        if (text->encoding_is_wchar) { n = text->length; memcpy(value, text->string.wide_char, (size_t)n*sizeof(wchar_t)); }
        else {
            const char *p = text->string.multi_byte; mbstate_t state = {0};
            for (int i=0; i<text->length; i++) { size_t bytes = mbrtowc(&value[n], p, MB_CUR_MAX, &state);
                if (!bytes || bytes == (size_t)-1 || bytes == (size_t)-2) return;
                p += bytes; n++;
            }
        }
    }
    if (mg.preedit_length-count+n > 4096) return;
    memmove(mg.preedit+first+n, mg.preedit+first+count, (size_t)(mg.preedit_length-first-count)*sizeof(wchar_t));
    memcpy(mg.preedit+first, value, (size_t)n*sizeof(wchar_t)); mg.preedit_length += n-count;
    mg.preedit_cursor = draw->caret; preedit_encode();
}
static void preedit_caret(XIC ic, XPointer client, XPointer call) {
    (void)ic; (void)client; XIMPreeditCaretCallbackStruct *caret = (void *)call;
    if (caret->direction == XIMAbsolutePosition) mg.preedit_cursor = caret->position;
    caret->position = mg.preedit_cursor; preedit_encode();
}
bool mg_open(mg_string title, int32_t width, int32_t height, bool headless) {
    if (mg.surface || width <= 0 || height <= 0) return false;
    memset(&mg, 0, sizeof(mg)); mg.scale = 1; mg.x = mg.y = -1;
    mg.headless = headless || mg_dump_requested();
    const char *renderer = getenv("MYGOOSE_RENDERER");
    if (renderer && strcmp(renderer, "cairo")) { fputs("MyGoose Linux renderer is cairo\n", stderr); return false; }
    if (!mg.headless) {
        setlocale(LC_CTYPE, ""); XSetLocaleModifiers("");
        mg.display = XOpenDisplay(NULL); if (!mg.display) { fputs("MyGoose: cannot open X11 display\n", stderr); return false; }
        const char *scale = getenv("MYGOOSE_SCALE");
        if (scale) { float s = strtof(scale, NULL); if (isfinite(s) && s >= 0.5f && s <= 4) mg.scale = s; }
    }
    buffer((int)ceilf(width*mg.scale), (int)ceilf(height*mg.scale));
    if (mg.headless) return true;
    int screen = DefaultScreen(mg.display);
    mg.window = XCreateSimpleWindow(mg.display, RootWindow(mg.display, screen), 0, 0, mg.width, mg.height, 0, 0, 0);
    char name[1024]; int n = (int)(title.len < 1023 ? title.len : 1023); if (n < 0) n=0;
    memcpy(name, title.data, (size_t)n); name[n] = 0; XStoreName(mg.display, mg.window, name);
    mg.close = XInternAtom(mg.display, "WM_DELETE_WINDOW", False); XSetWMProtocols(mg.display, mg.window, &mg.close, 1);
    mg.clipboard = XInternAtom(mg.display, "CLIPBOARD", False); mg.utf8 = XInternAtom(mg.display, "UTF8_STRING", False);
    mg.targets = XInternAtom(mg.display, "TARGETS", False); mg.transfer = XInternAtom(mg.display, "MYGOOSE_SELECTION", False);
    long events=ExposureMask|StructureNotifyMask|PointerMotionMask|ButtonPressMask|ButtonReleaseMask|KeyPressMask|FocusChangeMask|LeaveWindowMask;
    XSelectInput(mg.display, mg.window, events);
    mg.window_surface = cairo_xlib_surface_create(mg.display, mg.window, DefaultVisual(mg.display, screen), mg.width, mg.height);
    mg.im = XOpenIM(mg.display, NULL, NULL, NULL);
    if (mg.im) {
        XIMCallback start = {NULL, (XIMProc)preedit_start}, done = {NULL, (XIMProc)preedit_done};
        XIMCallback draw = {NULL, (XIMProc)preedit_draw}, caret = {NULL, (XIMProc)preedit_caret};
        XVaNestedList attrs = XVaCreateNestedList(0, XNPreeditStartCallback, &start, XNPreeditDoneCallback, &done,
            XNPreeditDrawCallback, &draw, XNPreeditCaretCallback, &caret, NULL);
        mg.ic = XCreateIC(mg.im, XNInputStyle, XIMPreeditCallbacks|XIMStatusNothing, XNClientWindow, mg.window,
            XNFocusWindow, mg.window, XNPreeditAttributes, attrs, NULL); XFree(attrs);
        if (!mg.ic) mg.ic = XCreateIC(mg.im, XNInputStyle, XIMPreeditNothing|XIMStatusNothing,
            XNClientWindow, mg.window, XNFocusWindow, mg.window, NULL);
        if (mg.ic) { long filter=0; XGetICValues(mg.ic,XNFilterEvents,&filter,NULL); XSelectInput(mg.display,mg.window,events|filter); }
    }
    if (!getenv("MYGOOSE_HIDDEN")) XMapWindow(mg.display, mg.window);
    XFlush(mg.display); return true;
}
void mg_close(void) {
    mg_capture(false);
    for (int i=0; i<64; i++) if (mg.layouts[i].layout) g_object_unref(mg.layouts[i].layout);
    if (mg.ic) XDestroyIC(mg.ic);
    if (mg.im) XCloseIM(mg.im);
        if (mg.resize_pointer) XFreeCursor(mg.display, mg.resize_pointer);
        if (mg.text_pointer) XFreeCursor(mg.display, mg.text_pointer);
    if (mg.window_surface) cairo_surface_destroy(mg.window_surface);
    if (mg.cr) cairo_destroy(mg.cr);
    if (mg.surface) cairo_surface_destroy(mg.surface);
    if (mg.display) { if (mg.window) XDestroyWindow(mg.display, mg.window); XCloseDisplay(mg.display); }
    memset(&mg, 0, sizeof(mg));
}
static void selection_request(XSelectionRequestEvent *r) {
    XEvent reply = {0}; reply.xselection = (XSelectionEvent){.type=SelectionNotify, .display=r->display,
        .requestor=r->requestor, .selection=r->selection, .target=r->target, .time=r->time, .property=None};
    Atom property = r->property ? r->property : r->target;
    if (r->selection == mg.clipboard && r->target == mg.targets) {
        Atom targets[2] = {mg.targets, mg.utf8};
        XChangeProperty(mg.display, r->requestor, property, XA_ATOM, 32, PropModeReplace, (unsigned char *)targets, 2); reply.xselection.property = property;
    } else if (r->selection == mg.clipboard && r->target == mg.utf8 && mg.clipboard_valid) {
        XChangeProperty(mg.display, r->requestor, property, mg.utf8, 8, PropModeReplace, mg.clipboard_text, mg.clipboard_length); reply.xselection.property = property;
    }
    XSendEvent(mg.display, r->requestor, False, 0, &reply); XFlush(mg.display);
}
static int key_code(KeySym key) {
    switch (key) { case XK_BackSpace: return 8; case XK_Tab: case XK_ISO_Left_Tab: return 9;
        case XK_Return: case XK_KP_Enter: return 13; case XK_Escape: return 27;
        case XK_Home: return 36; case XK_End: return 35; case XK_Left: return 37; case XK_Up: return 38;
        case XK_Right: return 39; case XK_Down: return 40; case XK_Delete: return 46; case XK_Insert: return 45;
        case XK_Page_Up: return 33; case XK_Page_Down: return 34;
        case XK_Menu: return 93; case XK_F10: return 121;
        default: return key >= 'a' && key <= 'z' ? (int)key-32 : (key < 128 ? (int)key : 0); }
}
static int dispatch(XEvent *e) {
    if (e->type == SelectionRequest) { selection_request(&e->xselectionrequest); return 0; }
    if (e->type == SelectionClear) { mg.clipboard_valid = false; return 0; }
    if (XFilterEvent(e, mg.window)) return 0;
    switch (e->type) {
    case Expose: present(true); break;
    case ConfigureNotify:
        if (mg.width != e->xconfigure.width || mg.height != e->xconfigure.height) { buffer(e->xconfigure.width, e->xconfigure.height); return 8; } break;
    case ClientMessage: if ((Atom)e->xclient.data.l[0] == mg.close) { mg.closed = true; return -1; } break;
    case FocusOut: if (mg.ic) XUnsetICFocus(mg.ic); return 7;
    case FocusIn: if (mg.ic && mg.ime_owner) XSetICFocus(mg.ic); break;
    case LeaveNotify: if (!(e->xcrossing.state & Button1Mask)) { mg.x = mg.y = -1; return 1; } break;
    case MotionNotify: mg.x = e->xmotion.x/mg.scale; mg.y = e->xmotion.y/mg.scale; return 1;
    case ButtonPress: case ButtonRelease: {
        XButtonEvent *b = &e->xbutton; mg.x = b->x/mg.scale; mg.y = b->y/mg.scale;
        mg.mods = ((b->state&ShiftMask)?1:0)|((b->state&ControlMask)?2:0);
        if (b->button == 4 || b->button == 5) { if (e->type == ButtonRelease) break; mg.delta = b->button == 4 ? 1 : -1; return 4; }
        if (b->button == 3 && e->type == ButtonRelease) return 14;
        if (b->button != 1) break;
        if (e->type == ButtonRelease) { mg_capture(false); return 3; }
        if (mg.ic && mg.preedit_length) {
            char *discard=Xutf8ResetIC(mg.ic); if (discard) XFree(discard);
            mg.preedit_length=mg.ime_length=mg.pending=0;
        }
        mg.click_count = mg.click_count && b->time-mg.click_time <= 500 && abs(b->x-mg.click_x)<=4 && abs(b->y-mg.click_y)<=4 ? mg.click_count%3+1 : 1;
        mg.click_time=b->time; mg.click_x=b->x; mg.click_y=b->y; mg.code=mg.click_count;
        return 2;
    }
    case KeyPress: {
        XKeyEvent *k = &e->xkey; KeySym key = XLookupKeysym(k, 0);
        mg.mods = ((k->state&ShiftMask)?1:0)|((k->state&ControlMask)?2:0); mg.code = key_code(key);
        if (k->state&(ControlMask|Mod1Mask)) return 5;
        char bytes[65536]; Status status = 0; int n;
        if (mg.ic) n = Xutf8LookupString(mg.ic, k, bytes, sizeof(bytes), &key, &status);
        else n = XLookupString(k, bytes, sizeof(bytes), &key, NULL);
        if (status == XBufferOverflow || n <= 0) return mg.preedit_length ? 0 : 5;
        // XLookupString also returns control bytes for Return/Tab/Backspace.
        // These remain normalized key events, not committed document text.
        if (n==1 && ((uint8_t)bytes[0]<32 || (uint8_t)bytes[0]==127)) return 5;
        if (mg.ime_owner) { memcpy(mg.result, bytes, (size_t)n); mg.result_length=n; mg.pending=0; return 11; }
        return 5;
    }
    } return 0;
}
bool mg_display_sync(int32_t fps) { (void)fps; return false; }
int32_t mg_display_hz(void) { return 0; }
int64_t mg_frame_time_ns(void) { return mg_clock_ns(); }
int32_t mg_wait(int32_t timeout_ms) {
    if (mg.headless || mg.closed) return -1;
    mg.delta = 0; int64_t until = timeout_ms > 0 ? mg_clock_ns()+(int64_t)timeout_ms*1000000 : INT64_MAX;
    for (;;) {
        if (mg.pending) { int kind=mg.pending; mg.pending=0; return kind; }
        if (XPending(mg.display)) { XEvent e; XNextEvent(mg.display, &e); int kind = dispatch(&e); if (kind) return kind; continue; }
        int64_t remaining = until-mg_clock_ns(); if (remaining <= 0) return 9;
        struct pollfd fd = {.fd=ConnectionNumber(mg.display), .events=POLLIN};
        int result = poll(&fd, 1, timeout_ms > 0 ? (int)((remaining+999999)/1000000) : -1);
        if (result < 0) { if (errno==EINTR) continue; return -1; }
        if (!result) return 9;
    }
}
float mg_event_x(void) { return mg.x; } float mg_event_y(void) { return mg.y; }
float mg_event_delta(void) { return mg.delta; } int32_t mg_event_code(void) { return mg.code; }
bool mg_event_scroll_pixels(void) { return false; }
int32_t mg_event_mods(void) { return mg.mods; }
float mg_width(void) { return mg.width/mg.scale; } float mg_height(void) { return mg.height/mg.scale; }
float mg_measure(mg_string text, float size, bool bold) {
    if (!mg.cr || text.len <= 0 || text.len > 65536) return 0;
    float width; layout(text, size, bold, &width); return width;
}
void mg_clip(float x, float y, float w, float h) {
    cairo_set_antialias(mg.cr, CAIRO_ANTIALIAS_NONE);
    cairo_reset_clip(mg.cr); cairo_rectangle(mg.cr, mg.dirty[0], mg.dirty[1], mg.dirty[2], mg.dirty[3]); cairo_clip(mg.cr);
    double left=floor(x*mg.scale)/mg.scale, top=floor(y*mg.scale)/mg.scale;
    cairo_rectangle(mg.cr, left, top, fmax(0,ceil((x+w)*mg.scale)/mg.scale-left), fmax(0,ceil((y+h)*mg.scale)/mg.scale-top)); cairo_clip(mg.cr);
    cairo_set_antialias(mg.cr, CAIRO_ANTIALIAS_DEFAULT);
}
static void rounded(float x, float y, float w, float h, float radius) {
    double r = fmax(0, fmin(radius, fmin(w,h)*0.5)); cairo_new_sub_path(mg.cr);
    cairo_arc(mg.cr, x+w-r, y+r, r, -M_PI/2, 0); cairo_arc(mg.cr, x+w-r, y+h-r, r, 0, M_PI/2);
    cairo_arc(mg.cr, x+r, y+h-r, r, M_PI/2, M_PI); cairo_arc(mg.cr, x+r, y+r, r, M_PI, 3*M_PI/2); cairo_close_path(mg.cr);
}
void mg_rect(float x, float y, float w, float h, float radius, uint32_t c) {
    if (w<=0 || h<=0) return;
    rounded(x,y,w,h,radius); color(c,1); cairo_fill(mg.cr);
}
void mg_shadow(float x, float y, float w, float h, float radius, float blur, float spread, float dx, float dy, uint32_t c, float opacity) {
    if (w<=0 || h<=0 || opacity<=0) return;
    for (int i=24; i>0; i--) {
        float expand = spread+blur*i/24.0f;
        rounded(x+dx-expand, y+dy-expand, w+2*expand, h+2*expand, radius+expand);
        color(c, opacity/24); cairo_fill(mg.cr);
    }
}
void mg_paint_begin(float x, float y, float w, float h, uint32_t background) {
    double left=floor(x*mg.scale)/mg.scale, top=floor(y*mg.scale)/mg.scale;
    mg.dirty[0]=left; mg.dirty[1]=top; mg.dirty[2]=ceil((x+w)*mg.scale)/mg.scale-left; mg.dirty[3]=ceil((y+h)*mg.scale)/mg.scale-top;
    mg_clip(left,top,mg.dirty[2],mg.dirty[3]); color(background,1); cairo_paint(mg.cr);
}
bool mg_paint_regions(mg_regions regions,uint32_t background) {
    mg_rect_region r=mg_region_bounds(regions);
    mg_paint_begin(r.x,r.y,r.w,r.h,background); return false;
}
void mg_text(mg_string text, float x, float y, float size, bool bold, uint32_t c) {
    if (text.len<=0 || text.len>65536) return;
    float width; PangoLayout *p=layout(text,size,bold,&width); color(c,1); cairo_move_to(mg.cr,x,y); pango_cairo_show_layout(mg.cr,p);
}
void mg_paint_end(void) { cairo_surface_flush(mg.surface); present(false); }
uint64_t mg_pixel_hash(void) {
    cairo_surface_flush(mg.surface); uint64_t hash=14695981039346656037ULL;
    for (int64_t i=0; i<(int64_t)mg.width*mg.height; i++) hash=(hash^(mg.pixels[i]&0xffffff))*1099511628211ULL;
    return hash;
}
bool mg_clipboard_set(mg_string text) {
    if (!mg.surface || text.len<0 || text.len>65536) return false;
    memcpy(mg.clipboard_text,text.data,(size_t)text.len); mg.clipboard_length=(int)text.len; mg.clipboard_valid=true;
    if (mg.headless) return true;
    XSetSelectionOwner(mg.display,mg.clipboard,mg.window,CurrentTime);
    return XGetSelectionOwner(mg.display,mg.clipboard)==mg.window;
}
int64_t mg_clipboard_get(mg_bytes out) {
    if (!mg.surface) return -1;
    if (mg.headless || XGetSelectionOwner(mg.display,mg.clipboard)==mg.window) {
        if (!mg.clipboard_valid || mg.clipboard_length>out.len) return -1;
        memcpy(out.data,mg.clipboard_text,(size_t)mg.clipboard_length); return mg.clipboard_length;
    }
    XConvertSelection(mg.display,mg.clipboard,mg.utf8,mg.transfer,mg.window,CurrentTime); XFlush(mg.display);
    int64_t until=mg_clock_ns()+500000000;
    while (mg_clock_ns()<until) {
        XEvent event;
        if (XCheckTypedEvent(mg.display,SelectionRequest,&event)) { selection_request(&event.xselectionrequest); continue; }
        if (XCheckTypedWindowEvent(mg.display,mg.window,SelectionNotify,&event)) {
            if (event.xselection.property==None) return -1;
            Atom type; int format; unsigned long count,remaining; unsigned char *data=NULL;
            int status=XGetWindowProperty(mg.display,mg.window,mg.transfer,0,16385,True,AnyPropertyType,&type,&format,&count,&remaining,&data);
            bool ok=status==Success && type==mg.utf8 && format==8 && !remaining && count<=(uint64_t)out.len;
            if (ok) memcpy(out.data,data,count);
            if (data) XFree(data);
            return ok ? (int64_t)count : -1;
        }
        struct pollfd fd={.fd=ConnectionNumber(mg.display),.events=POLLIN}; poll(&fd,1,5);
    } return -1;
}
void mg_ime_anchor(uint64_t owner, float x, float y, float w, float h, float size) {
    (void)w; (void)size;
    if (owner!=mg.ime_owner && mg.ic) {
        char *discard=Xutf8ResetIC(mg.ic); if (discard) XFree(discard);
        mg.preedit_length=mg.ime_length=mg.pending=0;
        if (owner) XSetICFocus(mg.ic); else XUnsetICFocus(mg.ic);
    }
    mg.ime_owner=owner; mg.spot=(XPoint){(short)(x*mg.scale),(short)((y+h)*mg.scale)};
    /* Spot attributes are accepted only by position-style XIMs. Callback
       XIMs own their candidate placement; inline preedit stays in Goose. */
}
int64_t mg_ime_read(mg_bytes out, bool result) {
    int n=result ? mg.result_length : mg.ime_length; if (n>out.len) n=0;
    memcpy(out.data,result ? mg.result : mg.ime_text,(size_t)n); return n;
}
int32_t mg_ime_cursor(void) { return mg.cursor; }
int32_t mg_ime_target_start(void) { return mg.cursor; } int32_t mg_ime_target_end(void) { return mg.cursor; }
int32_t mg_renderer(void) { return 2; }
int64_t mg_storage_bytes(void) { return sizeof(mg)+(int64_t)mg.width*mg.height*4; }
int64_t mg_memory_bytes(void) {
    FILE *file=fopen("/proc/self/statm","r"); long total=0,resident=0; if (!file) return -1;
    int read=fscanf(file,"%ld %ld",&total,&resident); fclose(file); return read==2 ? (int64_t)resident*sysconf(_SC_PAGESIZE) : -1;
}
bool mg_dump(void) {
    const char *path=getenv("MYGOOSE_DUMP"); if (!path || !*path) return false;
    FILE *file=fopen(path,"wb"); if (!file) return false;
    cairo_surface_flush(mg.surface); fprintf(file,"P6\n%d %d\n255\n",mg.width,mg.height); bool ok=true;
    for (int64_t i=0; i<(int64_t)mg.width*mg.height && ok; i++) { uint32_t p=mg.pixels[i]; uint8_t bytes[3]={(uint8_t)(p>>16),(uint8_t)(p>>8),(uint8_t)p}; ok=fwrite(bytes,1,3,file)==3; }
    return fclose(file)==0 && ok;
}
#include "../vector_target.h"
mg_vector_target mg_get_vector_target(void) {
    return (mg_vector_target){.context=mg.cr,.pixels=mg.pixels,.width=mg.width,.height=mg.height,.scale=mg.scale,.renderer=2};
}
