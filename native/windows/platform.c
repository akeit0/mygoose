/* MyGoose Windows CPU backend. Layout, controls, state and damage live in Goose.
   Direct2D/DirectWrite render into a retained 32-bit back buffer. */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <imm.h>
#include <psapi.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "../backend.h"
#include "../damage.h"
static struct {
    HWND window;
    HDC dc;
    HBITMAP bitmap, old_bitmap;
    uint32_t *pixels;
    int width, height, event, code, mods;
    HCURSOR pointer;
    float scale, x, y, delta;
    bool headless, closed, client_capture, releasing_capture, sizing;
    uint32_t background;
    void *caller_fiber, *dispatch_fiber;
    DWORD pump_thread;
    bool converted_thread, dispatching, stopping;
    int wait_timeout, wait_result;
    int64_t wait_deadline, animation_next_ns;
    HANDLE wait_timer;
    bool animations_active, scroll_smooth;
    RECT dirty;
    uint16_t high_surrogate;
    DWORD click_time;
    int click_x, click_y, click_count;
} mg;
#define MG_RESIZE_TIMER ((UINT_PTR)0x4d47525a)
static void mg_yield_event(void);
static void mg_yield_resize(void);
static void mg_pump_close(void);
// Private bridge for optional Windows frame extensions.
static bool mg_defer_show;
void *mg_windows_handle(void) { return mg.window; }
void mg_windows_defer_show(void) { mg_defer_show = true; }
// Separate reusable scratch storage from the platform's lifecycle state.
static WCHAR mg_wide_buffer[65537];
// Tests/headless apps have an isolated clipboard, never the user's clipboard.
static uint8_t mg_headless_clipboard[65536];
static int64_t mg_headless_clipboard_length;
static bool mg_headless_clipboard_valid;

static int mg_wide(mg_string s, WCHAR *out, int cap) {
    if (s.len < 0 || s.len > 65536 || cap <= 0) return 0;
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)s.data, (int)s.len, out, cap);
}
static int px(float v) { return (int)floorf(v * mg.scale); }
static int edge(float v) { return (int)ceilf(v * mg.scale); }
#include "draw_d2d.h"
#include "ime.h"
static void mg_buffer(int w, int h) {
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    if (w == mg.width && h == mg.height && mg.bitmap) return;
    if (w > 16384 || h > 16384 || (int64_t)w * h > 67108864) {
        fputs("MyGoose: window exceeds the 256 MiB framebuffer limit\n", stderr); exit(1);
    }
    BITMAPINFO info; memset(&info, 0, sizeof(info));
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = w; info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    void *pixels = NULL;
    HBITMAP next = CreateDIBSection(mg.dc, &info, DIB_RGB_COLORS, &pixels, NULL, 0);
    if (!next || !pixels) { fputs("MyGoose: cannot allocate framebuffer\n", stderr); exit(1); }
    /* A paint can arrive before Goose rebuilds the resized scene. Keep the
       overlapping frame and make every new pixel opaque, including its alpha
       byte: zero-filled DIBs can otherwise expose DWM glass during a drag. */
    GdiFlush();
    uint32_t *out = pixels;
    int width = mg.pixels ? (w < mg.width ? w : mg.width) : 0;
    int height = mg.pixels ? (h < mg.height ? h : mg.height) : 0;
    for (int y = 0; y < h; y++) {
        uint32_t *row = out+(int64_t)y*w;
        int copied = y < height ? width : 0;
        if (copied) memcpy(row,mg.pixels+(int64_t)y*mg.width,(size_t)copied*4);
        for (int x = copied; x < w; x++) row[x] = 0xff000000u | mg.background;
    }
    HBITMAP previous = (HBITMAP)SelectObject(mg.dc, next);
    if (mg.bitmap) DeleteObject(previous); else mg.old_bitmap = previous;
    mg.bitmap = next; mg.pixels = pixels; mg.width = w; mg.height = h;
    /* Also rebind after several native resizes return to the last painted
       dimensions: equal dimensions do not imply the same DIB is still bound. */
    d2d.width = d2d.height = 0;
}
static int modifiers(void) { return ((GetKeyState(VK_SHIFT) & 0x8000) ? 1 : 0) | ((GetKeyState(VK_CONTROL) & 0x8000) ? 2 : 0); }
static void mg_opaque_background(HDC dc, RECT r) {
    if (r.right <= r.left || r.bottom <= r.top) return;
    uint32_t pixel = 0xff000000u | mg.background;
    BITMAPINFO info = {.bmiHeader = {.biSize=sizeof(BITMAPINFOHEADER),.biWidth=1,.biHeight=-1,
        .biPlanes=1,.biBitCount=32,.biCompression=BI_RGB}};
    StretchDIBits(dc,r.left,r.top,r.right-r.left,r.bottom-r.top,0,0,1,1,&pixel,&info,DIB_RGB_COLORS,SRCCOPY);
}
static void mg_present(HDC dc, RECT r) {
    /* Native paint/erase can precede WM_SIZE. Cover any client area beyond the
       retained bitmap rather than reading outside its bounds or showing glass. */
    if (r.right > mg.width) {
        RECT strip = {r.left > mg.width ? r.left : mg.width,r.top,r.right,r.bottom};
        mg_opaque_background(dc,strip);
    }
    if (r.bottom > mg.height) {
        RECT strip = {r.left,r.top > mg.height ? r.top : mg.height,r.right,r.bottom};
        mg_opaque_background(dc,strip);
    }
    if (r.left < 0) r.left = 0;
    if (r.top < 0) r.top = 0;
    if (r.right > mg.width) r.right = mg.width;
    if (r.bottom > mg.height) r.bottom = mg.height;
    if (mg.bitmap && r.right > r.left && r.bottom > r.top)
        BitBlt(dc,r.left,r.top,r.right-r.left,r.bottom-r.top,mg.dc,r.left,r.top,SRCCOPY);
    /* Complete the blit before returning to User32/DWM's resize dispatch. */
    GdiFlush();
}
static void mg_present_window(HWND window) {
    RECT client;
    if (!mg.bitmap || !GetClientRect(window,&client) || IsIconic(window)) return;
    HDC dc = GetDC(window);
    if (dc) { mg_present(dc,client); ReleaseDC(window,dc); }
}
static LRESULT CALLBACK mg_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
    case WM_NCRBUTTONDOWN:
        if (wp == HTCAPTION) {
            /* Native caption clicks bypass client pointer events. Dismiss UI
               focus/popups before User32 enters its move/menu loop, while
               leaving the HWND focused and native caption behavior intact. */
            mg.event = 7; mg_yield_event();
            if (mg.stopping || mg.closed) return 0;
        }
        break;
    case WM_SETCURSOR:
        if (LOWORD(lp) == HTCLIENT && mg.pointer) { SetCursor(mg.pointer); return TRUE; }
        break;
    case WM_ERASEBKGND: {
        RECT client; GetClientRect(hwnd,&client); mg_present((HDC)wp,client); return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT p; HDC dc = BeginPaint(hwnd, &p);
        mg_present(dc,p.rcPaint);
        EndPaint(hwnd, &p); return 0;
    }
    case WM_SIZE:
        if (wp != SIZE_MINIMIZED && mg.dc) {
            mg_buffer(LOWORD(lp), HIWORD(lp)); mg.event = 8;
            /* Cover the resized surface before yielding to layout/sampling. */
            mg_present_window(hwnd);
            InvalidateRect(hwnd,NULL,FALSE); mg_yield_resize();
        }
        return 0;
    case WM_WINDOWPOSCHANGING:
        /* We retain pixels ourselves. User32's saved copy can otherwise
           overwrite a freshly rendered WM_SIZE frame with stale/black pixels. */
        if (!(((WINDOWPOS *)lp)->flags & SWP_NOSIZE)) ((WINDOWPOS *)lp)->flags |= SWP_NOCOPYBITS;
        break;
    case WM_WINDOWPOSCHANGED: {
        LRESULT result = DefWindowProcW(hwnd,msg,wp,lp);
        /* DefWindowProc synchronously sends WM_SIZE. Present again after its
           geometry processing finishes, including resizes outside the modal loop. */
        if (!(((WINDOWPOS *)lp)->flags & SWP_NOSIZE) && !mg.closed) mg_present_window(hwnd);
        return result;
    }
    case WM_ENTERSIZEMOVE:
        /* User32 now owns capture, even when its HWND matches a prior UI drag.
           Resize/layout cancellation may release only our client capture. */
        mg.client_capture = false;
        mg.sizing = true; SetTimer(hwnd,MG_RESIZE_TIMER,16,NULL); return 0;
    case WM_EXITSIZEMOVE:
        KillTimer(hwnd,MG_RESIZE_TIMER); mg.sizing = false; mg.event = 8;
        InvalidateRect(hwnd,NULL,FALSE); return 0;
    case WM_TIMER:
        if (wp == MG_RESIZE_TIMER) {
            if (mg.sizing) { mg.event = 9; mg_yield_resize(); }
            return 0;
        }
        break;
    case WM_DPICHANGED: {
        mg.scale = (float)HIWORD(wp) / 96.0f;
        RECT *r = (RECT *)lp;
        SetWindowPos(hwnd, NULL, r->left, r->top, r->right-r->left, r->bottom-r->top, SWP_NOZORDER | SWP_NOACTIVATE);
        mg.event = 8; return 0;
    }
    case WM_MOUSEMOVE: {
        mg.x = GET_X_LPARAM(lp) / mg.scale; mg.y = GET_Y_LPARAM(lp) / mg.scale; mg.event = 1;
        TRACKMOUSEEVENT t = {sizeof(t), TME_LEAVE, hwnd, 0}; TrackMouseEvent(&t); return 0;
    }
    case WM_MOUSELEAVE:
        if (GetCapture() != hwnd) { mg.x = mg.y = -1.0f; mg.event = 1; }
        return 0;
    case WM_LBUTTONDOWN: {
        if (ime.composing) {
            HIMC context = ImmGetContext(hwnd);
            if (context) { ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0); ImmReleaseContext(hwnd, context); }
            ime.composing = false; ime.length = 0; ime.pending_update = false;
        }
        DWORD now = (DWORD)GetMessageTime();
        int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
        if (mg.click_count && now-mg.click_time <= GetDoubleClickTime() &&
            abs(x-mg.click_x) <= GetSystemMetrics(SM_CXDOUBLECLK)/2 &&
            abs(y-mg.click_y) <= GetSystemMetrics(SM_CYDOUBLECLK)/2) mg.click_count = mg.click_count%3+1;
        else mg.click_count = 1;
        mg.click_time = now; mg.click_x = x; mg.click_y = y;
        SetFocus(hwnd); mg_capture(true); mg.event = 2;
        mg.code = mg.click_count;
        mg.x = GET_X_LPARAM(lp) / mg.scale; mg.y = GET_Y_LPARAM(lp) / mg.scale; return 0;
    }
    case WM_LBUTTONUP:
        mg_capture(false); mg.event = 3;
        mg.x = GET_X_LPARAM(lp) / mg.scale; mg.y = GET_Y_LPARAM(lp) / mg.scale; return 0;
    case WM_RBUTTONUP:
        mg.event = 14; mg.x = GET_X_LPARAM(lp) / mg.scale; mg.y = GET_Y_LPARAM(lp) / mg.scale; return 0;
    case WM_MOUSEWHEEL: {
        POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)}; ScreenToClient(hwnd, &p);
        mg.x = p.x / mg.scale; mg.y = p.y / mg.scale;
        int delta = GET_WHEEL_DELTA_WPARAM(wp);
        mg.scroll_smooth = delta && delta % WHEEL_DELTA == 0;
        mg.delta = (float)delta/WHEEL_DELTA; mg.event = 4;
        return 0;
    }
    case WM_KEYDOWN:
        if (ime.composing || wp == VK_PROCESSKEY) return 0;
        mg.code = (int)wp; mg.event = 5; return 0;
    case WM_IME_SETCONTEXT:
        return DefWindowProcW(hwnd, msg, wp, lp & ~((LPARAM)ISC_SHOWUICOMPOSITIONWINDOW));
    case WM_IME_STARTCOMPOSITION:
        ime.composing = true; ime.length = 0; ime.cursor = 0; ime.target_start = ime.target_end = 0;
        mg.event = 10; return 0;
    case WM_IME_COMPOSITION: ime_capture(hwnd, lp); return 0;
    case WM_IME_ENDCOMPOSITION:
        ime.composing = false; ime.length = 0; ime.pending_update = false; mg.event = 12; return 0;
    case WM_IME_CHAR: return 0; // GCS_RESULTSTR is committed by the app, once.
    case WM_IME_NOTIFY:
        if (wp == IMN_OPENCANDIDATE || wp == IMN_CHANGECANDIDATE) {
            HIMC context = ImmGetContext(hwnd);
            if (context) { ime_position(hwnd, context, lp ? (DWORD)lp : 1); ImmReleaseContext(hwnd, context); }
        }
        return DefWindowProcW(hwnd, msg, wp, lp);
    case WM_CHAR: {
        if (ime.composing) return 0;
        uint32_t ch = (uint32_t)wp;
        if (ch >= 0xd800 && ch <= 0xdbff) { mg.high_surrogate = (uint16_t)ch; return 0; }
        if (ch >= 0xdc00 && ch <= 0xdfff) {
            if (!mg.high_surrogate) return 0;
            ch = 0x10000 + (((uint32_t)mg.high_surrogate - 0xd800) << 10) + ch - 0xdc00;
        }
        mg.high_surrogate = 0;
        if (ch >= 32 && ch != 127) { mg.code = (int)ch; mg.event = 6; }
        return 0;
    }
    case WM_UNICHAR: if (wp == UNICODE_NOCHAR) return TRUE; mg.code = (int)wp; mg.event = 6; return 0;
    case WM_CAPTURECHANGED:
        if ((HWND)lp != hwnd) {
            bool owned = mg.client_capture; mg.client_capture = false;
            if (owned && !mg.releasing_capture) mg.event = 13;
        }
        return 0;
    case WM_SETFOCUS: {
        HIMC context = ImmGetContext(hwnd);
        if (context) { ime_position(hwnd, context, 1); ImmReleaseContext(hwnd, context); }
        return 0;
    }
    case WM_KILLFOCUS:
        if (ime.system_caret) { DestroyCaret(); ime.system_caret = false; }
        ime.composing = false; ime.length = 0; ime.pending_update = false;
        mg.high_surrogate = 0; mg.event = 7; return 0;
    case WM_CLOSE: DestroyWindow(hwnd); return 0;
    case WM_DESTROY: mg.closed = true; PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

bool mg_dump_requested(void) { const char *s = getenv("MYGOOSE_DUMP"); return s && *s; }
bool mg_capture(bool enabled) {
    if (mg.headless) return true;
    if (!mg.window) return !enabled;
    if (enabled) {
        if (mg.sizing) return false;
        if (GetCapture() != mg.window) SetCapture(mg.window);
        mg.client_capture = GetCapture() == mg.window;
        return mg.client_capture;
    }
    bool owned = mg.client_capture; mg.client_capture = false;
    if (owned && GetCapture() == mg.window) {
        mg.releasing_capture = true; ReleaseCapture(); mg.releasing_capture = false;
    }
    return !owned || GetCapture() != mg.window;
}
void mg_cursor(int32_t shape) {
    if (!mg.window || mg.headless) return;
    HCURSOR next = shape == 1 ? LoadCursor(NULL, IDC_SIZEWE) : shape == 2 ? LoadCursor(NULL, IDC_IBEAM) : NULL;
    /* A UI layout can clear its cursor while User32 is dragging an edge. */
    if (mg.sizing) { mg.pointer = next; return; }
    if (next == mg.pointer) return;
    mg.pointer = next;
    POINT point; RECT client;
    if (GetCursorPos(&point) && (GetCapture() == mg.window || WindowFromPoint(point) == mg.window)) {
        ScreenToClient(mg.window, &point); GetClientRect(mg.window, &client);
        if (GetCapture() == mg.window || PtInRect(&client, point)) SetCursor(next ? next : LoadCursor(NULL, IDC_ARROW));
    }
}
bool mg_open(mg_string title, int32_t width, int32_t height, bool headless) {
    if (mg.dc || width <= 0 || height <= 0) return false;
    const char *renderer = getenv("MYGOOSE_RENDERER");
    if (renderer && strcmp(renderer, "d2d")) {
        fputs("MyGoose: Windows requires Direct2D/DirectWrite (MYGOOSE_RENDERER=d2d)\n", stderr); return false;
    }
    bool defer_show = mg_defer_show; mg_defer_show = false;
    memset(&mg, 0, sizeof(mg)); mg.scale = 1.0f; mg.x = mg.y = -1.0f;
    mg.headless = headless || mg_dump_requested();
    if (mg.headless) { mg_headless_clipboard_valid = false; mg_headless_clipboard_length = 0; }
    if (!mg.headless) {
        HMODULE u = GetModuleHandleW(L"user32.dll");
        typedef BOOL (WINAPI *set_dpi_fn)(HANDLE);
        set_dpi_fn set_dpi = (set_dpi_fn)(void *)GetProcAddress(u, "SetProcessDpiAwarenessContext");
        if (set_dpi) set_dpi((HANDLE)(intptr_t)-4);
        typedef UINT (WINAPI *dpi_fn)(void);
        dpi_fn dpi = (dpi_fn)(void *)GetProcAddress(u, "GetDpiForSystem");
        if (dpi) mg.scale = dpi() / 96.0f;
    }
    mg.dc = CreateCompatibleDC(NULL); if (!mg.dc) return false;
    SetBkMode(mg.dc, TRANSPARENT); SetTextAlign(mg.dc, TA_LEFT | TA_TOP | TA_NOUPDATECP);
    mg_buffer(px((float)width), px((float)height));
    if (!d2d_open()) {
        fputs("MyGoose: Direct2D/DirectWrite initialization failed\n", stderr);
        mg_close(); return false;
    }
    if (mg.headless) return true;
    WNDCLASSW wc; memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = mg_proc; wc.hInstance = GetModuleHandleW(NULL); wc.lpszClassName = L"MyGoose.Window";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
    WCHAR name[1024]; int len = mg_wide(title, name, 1023); name[len] = 0;
    RECT rect = {0, 0, mg.width, mg.height}; AdjustWindowRectEx(&rect, WS_OVERLAPPEDWINDOW, FALSE, 0);
    mg.window = CreateWindowExW(0, wc.lpszClassName, name, WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, rect.right-rect.left, rect.bottom-rect.top,
        NULL, NULL, wc.hInstance, NULL);
    if (!mg.window) return false;
    ime.context = ImmGetContext(mg.window);
    if (ime.context) ImmReleaseContext(mg.window, ime.context);
    if (!defer_show && !getenv("MYGOOSE_HIDDEN")) ShowWindow(mg.window, SW_SHOW);
    return true;
}
void mg_close(void) {
    mg_pump_close();
    if (mg.wait_timer) CloseHandle(mg.wait_timer);
    if (mg.window) KillTimer(mg.window,MG_RESIZE_TIMER);
    if (ime.system_caret) DestroyCaret();
    if (mg.window && ime.context) ImmAssociateContext(mg.window, ime.context);
    memset(&ime, 0, sizeof(ime));
    d2d_close();
    if (mg.window && IsWindow(mg.window)) DestroyWindow(mg.window);
    if (mg.dc) {
        if (mg.bitmap) { SelectObject(mg.dc, mg.old_bitmap); DeleteObject(mg.bitmap); }
        DeleteDC(mg.dc);
    }
    memset(&mg, 0, sizeof(mg));
    // Allow a second native window in the same process after WM_QUIT.
    MSG msg; while (PeekMessageW(&msg, NULL, WM_QUIT, WM_QUIT, PM_REMOVE)) {}
}
static int mg_dispatch_messages(void) {
    MSG msg;
    while (!mg.event) {
        if (mg.stopping || mg.closed) return -1;
        if (ime.pending_update) { ime.pending_update = false; return 10; }
        /* Input wins over an overdue animation wake, including under heavy
           work. Controls will still sample motion on the resulting frame. */
        bool queued = PeekMessageW(&msg,NULL,0,0,PM_REMOVE);
        if (queued) {
            if (msg.message == WM_QUIT) return -1;
            TranslateMessage(&msg); DispatchMessageW(&msg);
        }
        // PeekMessage can itself dispatch sent messages (resize/close).
        if (mg.stopping || mg.closed) return -1;
        if (mg.event) break;
        int64_t now = mg_clock_ns();
        if (mg.wait_timeout > 0 && now >= mg.wait_deadline) return 9;
        if (mg.animations_active && now >= mg.animation_next_ns) {
            mg.animation_next_ns += ((now-mg.animation_next_ns)/8333333+1)*8333333;
            return MG_EVENT_ANIMATION;
        }
        if (queued) continue;
        int64_t deadline = mg.wait_timeout > 0 ? mg.wait_deadline : INT64_MAX;
        if (mg.animations_active && mg.animation_next_ns < deadline) deadline = mg.animation_next_ns;
        DWORD timeout = INFINITE, count = 0;
        if (deadline != INT64_MAX) {
            int64_t remaining = deadline-now;
            /* A per-window high-resolution wait avoids the coarse millisecond
               message timeout. Never change the system-wide timer period. */
            LARGE_INTEGER due; due.QuadPart = -(remaining+99)/100;
            if (mg.wait_timer && SetWaitableTimer(mg.wait_timer,&due,0,NULL,NULL,FALSE)) count = 1;
            else timeout = (DWORD)((remaining+999999)/1000000);
        }
        DWORD ready = MsgWaitForMultipleObjectsEx(count,count ? &mg.wait_timer : NULL,timeout,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
        if (ready == WAIT_TIMEOUT) continue;
        if (ready == WAIT_FAILED) return -1;
        if (count && ready == WAIT_OBJECT_0) continue;
    }
    mg.mods = modifiers(); return mg.event;
}
static void WINAPI mg_dispatch_main(void *unused) {
    (void)unused;
    for (;;) {
        /* Sent messages can also invoke WndProc from inside PeekMessage or
           MsgWait, so the entire native wait is active until it unwinds. */
        mg.dispatching = true;
        mg.wait_result = mg_dispatch_messages();
        mg.dispatching = false;
        SwitchToFiber(mg.caller_fiber);
    }
}
static bool mg_pump_start(void) {
    if (mg.dispatch_fiber) return mg.pump_thread == GetCurrentThreadId() && GetCurrentFiber() == mg.caller_fiber;
    mg.pump_thread = GetCurrentThreadId();
    if (IsThreadAFiber()) mg.caller_fiber = GetCurrentFiber();
    else {
        mg.caller_fiber = ConvertThreadToFiberEx(NULL,FIBER_FLAG_FLOAT_SWITCH);
        mg.converted_thread = mg.caller_fiber != NULL;
    }
    if (!mg.caller_fiber) return false;
    /* One native stack, lazily committed. Goose and D2D always execute on the
       caller fiber of this same UI thread; no Goose function values escape. */
    mg.dispatch_fiber = CreateFiberEx(16384,1048576,FIBER_FLAG_FLOAT_SWITCH,mg_dispatch_main,NULL);
    if (!mg.dispatch_fiber) {
        if (mg.converted_thread) ConvertFiberToThread();
        mg.caller_fiber = NULL; mg.converted_thread = false; return false;
    }
    mg.wait_timer = CreateWaitableTimerExW(NULL,NULL,CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,TIMER_MODIFY_STATE|SYNCHRONIZE);
    if (!mg.wait_timer) mg.wait_timer = CreateWaitableTimerW(NULL,FALSE,NULL);
    return true;
}
static void mg_yield_event(void) {
    /* Return to ordinary Goose event/layout/paint handling before a native
       callback continues, without reentering Goose from that callback. */
    if (mg.stopping || !mg.dispatch_fiber || GetCurrentFiber() != mg.dispatch_fiber) return;
    mg.mods = modifiers(); mg.wait_result = mg.event;
    SwitchToFiber(mg.caller_fiber);
}
static void mg_yield_resize(void) {
    if (mg.sizing) mg_yield_event();
}
static void mg_pump_close(void) {
    if (!mg.dispatch_fiber) return;
    mg.stopping = true;
    if (mg.dispatching) {
        /* Unwind a suspended User32 callback before freeing its native stack. */
        if (mg.window && IsWindow(mg.window)) {
            SendMessageW(mg.window,WM_CANCELMODE,0,0);
            PostMessageW(mg.window,WM_CLOSE,0,0);
        }
        SwitchToFiber(mg.dispatch_fiber);
    }
    DeleteFiber(mg.dispatch_fiber); mg.dispatch_fiber = NULL;
    if (mg.converted_thread) ConvertFiberToThread();
    mg.caller_fiber = NULL; mg.converted_thread = false;
}
bool mg_display_sync(int32_t fps) { (void)fps; return false; }
void mg_animation_pending(bool active) {
    if (active && !mg.animations_active) mg.animation_next_ns = mg_clock_ns()+8333333;
    mg.animations_active = active;
}
int32_t mg_display_hz(void) { return 0; }
int64_t mg_frame_time_ns(void) { return mg_clock_ns(); }
int32_t mg_wait(int32_t timeout_ms) {
    if (mg.headless || mg.closed) return -1;
    if (ime.pending_update) { ime.pending_update = false; return 10; }
    if (!mg_pump_start()) { fputs("MyGoose: cannot initialize the UI event pump\n",stderr); return -1; }
    mg.event = 0; mg.delta = 0.0f; mg.scroll_smooth = false; mg.wait_timeout = timeout_ms;
    mg.wait_deadline = mg_clock_ns()+(timeout_ms>0 ? (int64_t)timeout_ms*1000000 : 0);
    SwitchToFiber(mg.dispatch_fiber);
    return mg.wait_result;
}
float mg_event_x(void) { return mg.x; } float mg_event_y(void) { return mg.y; }
int32_t mg_event_code(void) { return mg.code; } int32_t mg_event_mods(void) { return mg.mods; }
float mg_event_delta(void) { return mg.delta; }
bool mg_event_scroll_pixels(void) { return false; }
bool mg_event_scroll_smooth(void) { return mg.scroll_smooth; }
float mg_width(void) { return mg.width / mg.scale; } float mg_height(void) { return mg.height / mg.scale; }
float mg_measure(mg_string text, float size, bool bold) {
    return mg.dc && text.len ? d2d_layout(text, size, bold)->width : 0.0f;
}
void mg_clip(float x, float y, float w, float h) { d2d_clip(x,y,w,h); }
void mg_rect(float x, float y, float w, float h, float radius, uint32_t color) { d2d_rect(x,y,w,h,radius,color); }
void mg_shadow(float x, float y, float w, float h, float radius, float blur,
               float spread, float dx, float dy, uint32_t color, float opacity) {
    if (w > 0 && h > 0 && opacity > 0) d2d_shadow(x,y,w,h,radius,blur,spread,dx,dy,color,opacity);
}
void mg_paint_begin(float x, float y, float w, float h, uint32_t background) {
    mg.background = background & 0xffffff;
    mg.dirty = (RECT){px(x), px(y), edge(x+w), edge(y+h)};
    d2d_begin(x,y,w,h,background);
}
bool mg_paint_regions(mg_regions regions,uint32_t background) {
    mg_rect_region r=mg_region_bounds(regions);
    mg.background = background & 0xffffff;
    mg.dirty = (RECT){px(r.x),px(r.y),edge(r.x+r.w),edge(r.y+r.h)};
    if (regions.len > 1) return d2d_begin_regions(regions,r,background);
    mg_paint_begin(r.x,r.y,r.w,r.h,background); return false;
}
void mg_text(mg_string text, float x, float y, float size, bool bold, uint32_t color) { d2d_text(text,x,y,size,bold,color); }
uint64_t mg_pixel_hash(void) {
    GdiFlush(); uint64_t h = 14695981039346656037ULL;
    for (int64_t i = 0; i < (int64_t)mg.width * mg.height; i++) h = (h ^ (mg.pixels[i] & 0xffffff)) * 1099511628211ULL;
    return h;
}
void mg_paint_end(void) {
    d2d_end();
    GdiFlush();
    if (mg.window) {
        HDC dc = GetDC(mg.window);
        mg_present(dc,mg.dirty);
        ReleaseDC(mg.window, dc); ValidateRect(mg.window, &mg.dirty);
    }
}
static int clipboard_encode(mg_string text, WCHAR *out, int capacity) {
    if (text.len < 0 || text.len > 65536) return -1;
    int units = mg_wide(text, mg_wide_buffer, 65536), n = 0;
    if (text.len && !units) return -1;
    for (int i = 0; i < units; i++) {
        WCHAR ch = mg_wide_buffer[i];
        if (ch == L'\r' || ch == L'\n') {
            if (out) { if (n+2 >= capacity) return -1; out[n] = L'\r'; out[n+1] = L'\n'; }
            n += 2;
            if (ch == L'\r' && i+1 < units && mg_wide_buffer[i+1] == L'\n') i++;
        } else {
            if (out) { if (n+1 >= capacity) return -1; out[n] = ch; }
            n++;
        }
    }
    if (out) out[n] = 0;
    return n;
}
bool mg_clipboard_set(mg_string text) {
    if (text.len < 0 || text.len > 65536) return false;
    if (mg.headless) {
        memcpy(mg_headless_clipboard, text.data, (size_t)text.len);
        mg_headless_clipboard_length = text.len; mg_headless_clipboard_valid = true; return true;
    }
    if (!mg.window) return false;
    int length = clipboard_encode(text, NULL, 0); if (length < 0) return false;
    HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, ((size_t)length+1)*sizeof(WCHAR));
    if (!mem) return false;
    WCHAR *p = GlobalLock(mem);
    if (!p) { GlobalFree(mem); return false; }
    int len = clipboard_encode(text, p, length+1);
    GlobalUnlock(mem);
    if (len < 0) { GlobalFree(mem); return false; }
    if (!OpenClipboard(mg.window)) { GlobalFree(mem); return false; }
    bool ok = EmptyClipboard() && SetClipboardData(CF_UNICODETEXT, mem) != NULL;
    CloseClipboard();
    if (!ok) GlobalFree(mem);
    return ok;
}
static int clipboard_decode(const WCHAR *p, int length, mg_bytes out) {
    int n = 0;
    for (int i = 0; i < length; i++) {
        WCHAR ch = p[i];
        if (ch == L'\r') { if (i+1 < length && p[i+1] == L'\n') i++; ch = L'\n'; }
        if (n >= 65536 || n >= out.len) return -1;
        mg_wide_buffer[n++] = ch;
    }
    int need = n ? WideCharToMultiByte(CP_UTF8, 0, mg_wide_buffer, n, NULL, 0, NULL, NULL) : 0;
    if (need > out.len || (n && !need)) return -1;
    int result = need ? WideCharToMultiByte(CP_UTF8, 0, mg_wide_buffer, n, (char *)out.data, need, NULL, NULL) : 0;
    return need && !result ? -1 : result;
}
int64_t mg_clipboard_get(mg_bytes out) {
    if (mg.headless) {
        if (!mg_headless_clipboard_valid || mg_headless_clipboard_length > out.len) return -1;
        memcpy(out.data, mg_headless_clipboard, (size_t)mg_headless_clipboard_length);
        return mg_headless_clipboard_length;
    }
    if (!OpenClipboard(mg.window)) return -1;
    HANDLE mem = GetClipboardData(CF_UNICODETEXT); const WCHAR *p = mem ? GlobalLock(mem) : NULL;
    int n = -1;
    if (p) {
        SIZE_T capacity = GlobalSize(mem)/sizeof(WCHAR), length = 0;
        while (length < capacity && p[length]) length++;
        if (length < capacity && length <= 0x7fffffff) {
            n = clipboard_decode(p, (int)length, out);
        }
        GlobalUnlock(mem);
    }
    CloseClipboard(); return n;
}
bool mg_dump(void) {
    const char *path = getenv("MYGOOSE_DUMP"); if (!path || !*path) return false;
    FILE *file = fopen(path, "wb"); if (!file) return false;
    fprintf(file, "P6\n%d %d\n255\n", mg.width, mg.height);
    GdiFlush(); bool ok = true;
    for (int y = 0; y < mg.height && ok; y++) for (int x = 0; x < mg.width; x++) {
        uint32_t p = mg.pixels[(int64_t)y*mg.width+x];
        uint8_t rgb_bytes[3] = {(uint8_t)(p>>16), (uint8_t)(p>>8), (uint8_t)p};
        if (fwrite(rgb_bytes, 1, 3, file) != 3) { ok = false; break; }
    }
    if (fclose(file) != 0) ok = false;
    return ok;
}
int64_t mg_clock_ns(void) {
    LARGE_INTEGER f, t; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t);
    return t.QuadPart / f.QuadPart * 1000000000LL + t.QuadPart % f.QuadPart * 1000000000LL / f.QuadPart;
}
int64_t mg_memory_bytes(void) {
    PROCESS_MEMORY_COUNTERS_EX m; memset(&m, 0, sizeof(m)); m.cb = sizeof(m);
    typedef BOOL (WINAPI *memory_fn)(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD);
    memory_fn f = (memory_fn)(void *)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "K32GetProcessMemoryInfo");
    if (!f || !f(GetCurrentProcess(), (PPROCESS_MEMORY_COUNTERS)&m, sizeof(m))) return -1;
    return (int64_t)m.WorkingSetSize;
}
int64_t mg_cpu_ns(void) {
    FILETIME created,exited,kernel,user;
    if (!GetProcessTimes(GetCurrentProcess(),&created,&exited,&kernel,&user)) return -1;
    uint64_t k=((uint64_t)kernel.dwHighDateTime<<32)|kernel.dwLowDateTime;
    uint64_t u=((uint64_t)user.dwHighDateTime<<32)|user.dwLowDateTime;
    return (int64_t)((k+u)*100);
}
int64_t mg_storage_bytes(void) { return sizeof(mg) + sizeof(mg_wide_buffer) + sizeof(ime) + sizeof(d2d) +
    (mg.headless ? sizeof(mg_headless_clipboard) : 0) + (int64_t)mg.width * mg.height * 4; }
int32_t mg_renderer(void) { return 1; }
#include "../vector_target.h"
mg_vector_target mg_get_vector_target(void) {
    mg_vector_target result={.context=mg.dc,.pixels=mg.pixels,.width=mg.width,.height=mg.height,.scale=mg.scale};
    result.factory=d2d.factory; result.target=d2d.target; result.brush=d2d.brush; result.renderer=1;
    return result;
}
