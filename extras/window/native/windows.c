#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include "../../../native/backend.h"

void *mg_windows_handle(void);
void mg_windows_defer_show(void);
typedef struct { float x, y, w, h; } frame_rect;
static struct {
    HWND window; WNDPROC previous; LONG_PTR caption_style;
    frame_rect drag, clients[32]; int count;
    bool enabled, overflow; float minimum_width, minimum_height;
} frame;
static bool frame_prepared;
bool mg_window_native_controls(void) { return false; }
/* Undocumented themed non-client paint messages also used by Chromium's
   custom frame. WM_NCPAINT alone does not intercept these drawing paths. */
#define MG_WM_NCUAHDRAWCAPTION 0x00ae
#define MG_WM_NCUAHDRAWFRAME 0x00af
static float frame_scale(HWND window) {
    typedef UINT (WINAPI *dpi_fn)(HWND);
    dpi_fn dpi = (dpi_fn)(void *)GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow");
    if (dpi) return dpi(window) / 96.0f;
    RECT client; GetClientRect(window, &client);
    return client.right > 0 && mg_width() > 0 ? client.right / mg_width() : 1.0f;
}
static bool frame_contains(frame_rect r, float x, float y) { return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h; }
static LRESULT frame_hit_at(int width, int height, POINT client, float scale, bool maximized) {
    if (!maximized) {
        int border = (int)(6 * scale + .5f);
        bool left = client.x < border, right = client.x >= width - border;
        bool top = client.y < border, bottom = client.y >= height - border;
        if (top && left) return HTTOPLEFT;
        if (top && right) return HTTOPRIGHT;
        if (bottom && left) return HTBOTTOMLEFT;
        if (bottom && right) return HTBOTTOMRIGHT;
        if (left) return HTLEFT;
        if (right) return HTRIGHT;
        if (top) return HTTOP;
        if (bottom) return HTBOTTOM;
    }
    float x = client.x / scale, y = client.y / scale;
    for (int i = 0; i < frame.count; ++i) if (frame_contains(frame.clients[i], x, y)) return HTCLIENT;
    return !frame.overflow && frame_contains(frame.drag, x, y) ? HTCAPTION : HTCLIENT;
}
static LRESULT frame_hit(HWND window, POINT screen) {
    RECT client; GetClientRect(window, &client); ScreenToClient(window, &screen);
    return frame_hit_at(client.right, client.bottom, screen, frame_scale(window), IsZoomed(window) || IsIconic(window));
}
static void frame_shadow(HWND window) {
    MARGINS margins = {1, 1, 1, 1}; DwmExtendFrameIntoClientArea(window, &margins);
    int corner = 2; DwmSetWindowAttribute(window, 33, &corner, sizeof corner); /* Windows 11 rounded corners. */
}
static LRESULT frame_without_redraw(HWND window, WNDPROC previous, UINT message, WPARAM w, LPARAM l) {
    /* DefWindowProc paints directly during metadata/theme/activation updates. Clearing
       only WS_VISIBLE prevents that synchronous paint without hiding/showing
       the HWND, changing its caption style, or disabling DWM transitions.
       Never run this guard around minimize/maximize/restore commands. */
    LONG_PTR visible = GetWindowLongPtrW(window, GWL_STYLE) & WS_VISIBLE;
    if (visible) SetWindowLongPtrW(window, GWL_STYLE, GetWindowLongPtrW(window, GWL_STYLE) & ~((LONG_PTR)WS_VISIBLE));
    LRESULT result = CallWindowProcW(previous, window, message, w, l);
    if (visible && IsWindow(window)) SetWindowLongPtrW(window, GWL_STYLE, GetWindowLongPtrW(window, GWL_STYLE) | WS_VISIBLE);
    return result;
}
static LRESULT CALLBACK frame_proc(HWND window, UINT message, WPARAM w, LPARAM l) {
    WNDPROC previous = frame.previous;
    if (message == WM_NCCALCSIZE) {
        if (IsZoomed(window)) {
            RECT *client = w ? &((NCCALCSIZE_PARAMS *)l)->rgrc[0] : (RECT *)l;
            MONITORINFO monitor = { .cbSize = sizeof monitor };
            if (GetMonitorInfoW(MonitorFromRect(client, MONITOR_DEFAULTTONEAREST), &monitor)) {
                if (client->left < monitor.rcWork.left) client->left = monitor.rcWork.left;
                if (client->top < monitor.rcWork.top) client->top = monitor.rcWork.top;
                if (client->right > monitor.rcWork.right) client->right = monitor.rcWork.right;
                if (client->bottom > monitor.rcWork.bottom) client->bottom = monitor.rcWork.bottom;
            }
        }
        return 0;
    }
    if (message == WM_NCHITTEST) return frame_hit(window, (POINT){GET_X_LPARAM(l), GET_Y_LPARAM(l)});
    if (message == WM_NCPAINT || message == MG_WM_NCUAHDRAWCAPTION || message == MG_WM_NCUAHDRAWFRAME) return 0;
    if (message == WM_NCACTIVATE) return frame_without_redraw(window, previous, message, w, -1);
    if (message == WM_SETTEXT || message == WM_SETICON || message == WM_THEMECHANGED ||
        message == WM_SYSCOLORCHANGE || message == WM_SETTINGCHANGE ||
        message == WM_ACTIVATE || message == WM_ACTIVATEAPP) return frame_without_redraw(window, previous, message, w, l);
    if (message == WM_SETCURSOR) {
        LPCTSTR cursor = NULL;
        switch (LOWORD(l)) {
        case HTCAPTION: cursor = IDC_ARROW; break;
        case HTLEFT: case HTRIGHT: cursor = IDC_SIZEWE; break;
        case HTTOP: case HTBOTTOM: cursor = IDC_SIZENS; break;
        case HTTOPLEFT: case HTBOTTOMRIGHT: cursor = IDC_SIZENWSE; break;
        case HTTOPRIGHT: case HTBOTTOMLEFT: cursor = IDC_SIZENESW; break;
        }
        if (cursor) { SetCursor(LoadCursor(NULL, cursor)); return TRUE; }
    }
    if (message == WM_GETMINMAXINFO) {
        LRESULT result = CallWindowProcW(previous, window, message, w, l);
        MINMAXINFO *limits = (MINMAXINFO *)l; MONITORINFO monitor = { .cbSize = sizeof monitor };
        if (GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) {
            limits->ptMaxPosition = (POINT){ monitor.rcWork.left - monitor.rcMonitor.left, monitor.rcWork.top - monitor.rcMonitor.top };
            limits->ptMaxSize = (POINT){ monitor.rcWork.right - monitor.rcWork.left, monitor.rcWork.bottom - monitor.rcWork.top };
        }
        float scale = frame_scale(window);
        limits->ptMinTrackSize = (POINT){ (LONG)(frame.minimum_width * scale), (LONG)(frame.minimum_height * scale) }; return result;
    }
    /* Frame extension survives activation changes. Reapplying it on blur can
       resurrect an inactive native caption even with WM_NCPAINT suppressed. */
    if (message == WM_DWMCOMPOSITIONCHANGED) {
        frame_shadow(window);
        return frame_without_redraw(window, previous, message, w, l);
    }
    if (message == WM_NCDESTROY) {
        LRESULT result = CallWindowProcW(previous, window, message, w, l);
        memset(&frame, 0, sizeof frame); return result;
    }
    return CallWindowProcW(previous, window, message, w, l);
}
void mg_window_prepare(void) { frame_prepared = true; mg_windows_defer_show(); }
bool mg_window_frame(bool enabled, float minimum_width, float minimum_height) {
    HWND window = (HWND)mg_windows_handle(); bool show = frame_prepared; frame_prepared = false;
    if (frame.window && IsWindow(frame.window) && frame.previous) {
        RECT client; GetClientRect(frame.window, &client);
        LONG_PTR style = (GetWindowLongPtrW(frame.window, GWL_STYLE) & ~((LONG_PTR)WS_CAPTION)) | frame.caption_style;
        AdjustWindowRectEx(&client, (DWORD)style, FALSE, (DWORD)GetWindowLongPtrW(frame.window, GWL_EXSTYLE));
        SetWindowLongPtrW(frame.window, GWLP_WNDPROC, (LONG_PTR)frame.previous);
        SetWindowLongPtrW(frame.window, GWL_STYLE, style);
        MARGINS margins = {0}; DwmExtendFrameIntoClientArea(frame.window, &margins);
        SetWindowPos(frame.window, NULL, 0, 0, client.right-client.left, client.bottom-client.top, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    memset(&frame, 0, sizeof frame);
    if (enabled) {
        frame.enabled = true; frame.minimum_width = minimum_width > 0 ? minimum_width : 320; frame.minimum_height = minimum_height > 0 ? minimum_height : 200;
        if (window) {
            RECT client; GetClientRect(window, &client); frame.window = window;
            SetLastError(0);
            frame.previous = (WNDPROC)SetWindowLongPtrW(window, GWLP_WNDPROC, (LONG_PTR)frame_proc);
            if (!frame.previous) { memset(&frame, 0, sizeof frame); }
            else {
                /* Retain native caption semantics for DWM minimize/restore
                   animation. NCCALCSIZE removes the visible frame; frame_proc
                   separately suppresses native caption painting. */
                LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
                frame.caption_style = style & WS_CAPTION;
                if (frame.caption_style != WS_CAPTION) SetWindowLongPtrW(window, GWL_STYLE, style | WS_CAPTION);
                frame_shadow(window);
                SetWindowPos(window, NULL, 0, 0, client.right, client.bottom, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
        }
    }
    if (show && window && !getenv("MYGOOSE_HIDDEN")) ShowWindow(window, SW_SHOW);
    return frame.enabled;
}
int32_t mg_window_state(void) { return frame.window && IsZoomed(frame.window) ? 1 : 0; }
bool mg_window_command(int32_t command) {
    if (!frame.window || !IsWindow(frame.window)) return false;
    if (command == 0) return PostMessageW(frame.window, WM_SYSCOMMAND, SC_MINIMIZE, 0) != 0;
    if (command == 1) return PostMessageW(frame.window, WM_SYSCOMMAND, IsZoomed(frame.window) || IsIconic(frame.window) ? SC_RESTORE : SC_MAXIMIZE, 0) != 0;
    if (command == 2) return PostMessageW(frame.window, WM_CLOSE, 0, 0) != 0;
    return false;
}
void mg_window_region(int32_t kind, float x, float y, float w, float h) {
    frame_rect rect = {x, y, w, h};
    if (kind == 0) { frame.count = 0; frame.overflow = false; frame.drag = (frame_rect){0}; }
    if (kind == 1) frame.drag = rect;
    if (kind == 2) { if (frame.count < 32) frame.clients[frame.count++] = rect; else frame.overflow = true; }
}
