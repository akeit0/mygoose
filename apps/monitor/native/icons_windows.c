#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>
#include <stdlib.h>
#include "../../../native/backend.h"

double mon_process_value(int32_t row, int32_t field);
uint64_t mon_process_birth(int32_t row);
double mon_detail_value(int32_t row, int32_t field);
uint64_t mon_detail_birth(int32_t row);
int64_t mg_image_create(mg_string rgba, int32_t width, int32_t height);
void mg_image_free(int64_t handle);

/* Cache images by executable path and PID lookups by creation time. Only
   visible processes are queried. Bounded LRU storage; no handles to processes
   or HICONs survive extraction. Negative lookups are cached too. */
typedef struct { wchar_t path[1024]; int64_t image; uint64_t used; uint8_t *rgba; int state; } mon_icon_entry;
typedef struct { DWORD pid; uint64_t birth, used; int slot; } mon_icon_pid;
static mon_icon_entry mon_icons[64];
static mon_icon_pid mon_icon_pids[512];
static uint64_t mon_icon_clock;
static CRITICAL_SECTION mon_icon_lock;
static HANDLE mon_icon_event, mon_icon_thread;
static bool mon_icon_started, mon_icon_stopping;
static uint8_t *mon_icon_extract(const wchar_t *path) {
    HICON icon = NULL;
    UINT count = ExtractIconExW(path, 0, &icon, NULL, 1);
    if (!count || count == UINT_MAX || !icon) { if (icon) DestroyIcon(icon); return NULL; }
    const int size = 32; uint8_t *result = NULL;
    BITMAPINFO bmi; memset(&bmi, 0, sizeof bmi); bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = size; bmi.bmiHeader.biHeight = -size;
    bmi.bmiHeader.biPlanes = 1; bmi.bmiHeader.biBitCount = 32; bmi.bmiHeader.biCompression = BI_RGB;
    HDC dc = CreateCompatibleDC(NULL); uint32_t *pixels = NULL;
    HBITMAP bitmap = dc ? CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, (void **)&pixels, NULL, 0) : NULL;
    if (bitmap) {
        HGDIOBJ old = SelectObject(dc, bitmap); uint32_t black[32*32]; uint8_t rgba[32*32*4];
        memset(pixels, 0, sizeof black);
        bool ok = DrawIconEx(dc, 0, 0, icon, size, size, 0, NULL, DI_NORMAL) != 0;
        GdiFlush(); memcpy(black, pixels, sizeof black); memset(pixels, 255, sizeof black);
        ok = DrawIconEx(dc, 0, 0, icon, size, size, 0, NULL, DI_NORMAL) != 0 && ok;
        GdiFlush();
        if (ok) {
            /* Black/white passes recover alpha for both modern ARGB icons
               and legacy mask icons, without a black background fringe. */
            for (int i = 0; i < size*size; ++i) {
                int br = (black[i] >> 16) & 255, bg = (black[i] >> 8) & 255, bb = black[i] & 255;
                int diff = (int)((pixels[i] >> 16) & 255) - br;
                int dg = (int)((pixels[i] >> 8) & 255) - bg, db = (int)(pixels[i] & 255) - bb;
                if (dg > diff) diff = dg;
                if (db > diff) diff = db;
                int a = 255 - (diff < 0 ? 0 : diff > 255 ? 255 : diff);
                rgba[i*4] = a ? (uint8_t)(br * 255 / a > 255 ? 255 : br * 255 / a) : 0;
                rgba[i*4+1] = a ? (uint8_t)(bg * 255 / a > 255 ? 255 : bg * 255 / a) : 0;
                rgba[i*4+2] = a ? (uint8_t)(bb * 255 / a > 255 ? 255 : bb * 255 / a) : 0;
                rgba[i*4+3] = (uint8_t)a;
            }
            result = malloc(sizeof rgba); if (result) memcpy(result, rgba, sizeof rgba);
        }
        SelectObject(dc, old); DeleteObject(bitmap);
    }
    if (dc) DeleteDC(dc);
    DestroyIcon(icon); return result;
}
/* Executable icon resource I/O runs on a worker. Renderer resources
   are created on the UI thread when ready RGBA pixels are consumed. */
static DWORD WINAPI mon_icon_worker(void *unused) {
    (void)unused;
    for (;;) {
        int job = -1; wchar_t path[1024];
        EnterCriticalSection(&mon_icon_lock);
        bool stop = mon_icon_stopping;
        if (!stop) for (int i = 0; i < 64; ++i) if (mon_icons[i].state == 1) {
            job = i; mon_icons[i].state = 2; wcscpy(path, mon_icons[i].path); break;
        }
        LeaveCriticalSection(&mon_icon_lock);
        if (stop) break;
        if (job < 0) { WaitForSingleObject(mon_icon_event, INFINITE); continue; }
        uint8_t *rgba = mon_icon_extract(path);
        EnterCriticalSection(&mon_icon_lock); mon_icons[job].rgba = rgba; mon_icons[job].state = 3; LeaveCriticalSection(&mon_icon_lock);
    }
    return 0;
}
static bool mon_icons_start(void) {
    if (mon_icon_started) return !mon_icon_stopping;
    InitializeCriticalSection(&mon_icon_lock);
    mon_icon_event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (mon_icon_event) mon_icon_thread = CreateThread(NULL, 0, mon_icon_worker, NULL, 0, NULL);
    if (!mon_icon_thread) {
        if (mon_icon_event) CloseHandle(mon_icon_event);
        mon_icon_event = NULL; DeleteCriticalSection(&mon_icon_lock); return false;
    }
    mon_icon_started = true; return true;
}
static int64_t mon_icon_consume(int index, uint64_t tick) {
    if (index < 0) return 0;
    mon_icon_entry *slot = &mon_icons[index]; slot->used = tick;
    if (slot->state == 3) {
        if (slot->rgba) { slot->image = mg_image_create((mg_string){slot->rgba, 32*32*4}, 32, 32); free(slot->rgba); slot->rgba = NULL; }
        slot->state = 4;
    }
    return slot->image;
}
static int64_t mon_icon_for_process(DWORD pid, uint64_t birth) {
    if (!pid || !mon_icons_start()) return 0;
    uint64_t tick = ++mon_icon_clock; int oldest_pid = 0;
    EnterCriticalSection(&mon_icon_lock);
    for (int i = 0; i < 512; ++i) {
        if (mon_icon_pids[i].pid == pid && mon_icon_pids[i].birth == birth) {
            mon_icon_pids[i].used = tick; int64_t image = mon_icon_consume(mon_icon_pids[i].slot, tick);
            LeaveCriticalSection(&mon_icon_lock); return image;
        }
        if (mon_icon_pids[i].used < mon_icon_pids[oldest_pid].used) oldest_pid = i;
    }
    LeaveCriticalSection(&mon_icon_lock);
    wchar_t path[1024]; DWORD size = 1024;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    FILETIME created, ended, kernel, user;
    bool have_path = process && GetProcessTimes(process, &created, &ended, &kernel, &user) &&
        (((uint64_t)created.dwHighDateTime << 32) | created.dwLowDateTime) == birth &&
        QueryFullProcessImageNameW(process, 0, path, &size);
    if (process) CloseHandle(process);
    EnterCriticalSection(&mon_icon_lock);
    int index = -1;
    if (have_path) {
        int oldest = -1;
        for (int i = 0; i < 64; ++i) {
            if (mon_icons[i].used && !wcscmp(mon_icons[i].path, path)) { index = i; break; }
            if ((mon_icons[i].state == 0 || mon_icons[i].state == 4) && (oldest < 0 || mon_icons[i].used < mon_icons[oldest].used)) oldest = i;
        }
        if (index < 0 && oldest >= 0) {
            index = oldest; mg_image_free(mon_icons[index].image);
            for (int i = 0; i < 512; ++i) if (mon_icon_pids[i].pid && mon_icon_pids[i].slot == index) memset(&mon_icon_pids[i], 0, sizeof mon_icon_pids[i]);
            memset(&mon_icons[index], 0, sizeof mon_icons[index]); wcscpy(mon_icons[index].path, path);
            mon_icons[index].state = 1; mon_icons[index].used = tick; SetEvent(mon_icon_event);
        }
    }
    // Queue saturation is retried on the next UI build, rather than caching
    // a permanent miss. Inaccessible paths are negative cached by PID.
    if (!have_path || index >= 0) mon_icon_pids[oldest_pid] = (mon_icon_pid){pid, birth, tick, index};
    int64_t image = mon_icon_consume(index, tick); LeaveCriticalSection(&mon_icon_lock); return image;
}
int64_t mon_process_icon(int32_t row) { return mon_icon_for_process((DWORD)mon_process_value(row, 0), mon_process_birth(row)); }
int64_t mon_detail_icon(int32_t row) { return mon_icon_for_process((DWORD)mon_detail_value(row, 0), mon_detail_birth(row)); }
bool mon_icons_pending(void) {
    if (!mon_icon_started) return false;
    bool pending = false; EnterCriticalSection(&mon_icon_lock);
    for (int i = 0; i < 64; ++i) {
        if (mon_icons[i].state == 3) { mon_icon_consume(i, mon_icons[i].used); pending = true; }
        if (mon_icons[i].state == 1 || mon_icons[i].state == 2) pending = true;
    }
    LeaveCriticalSection(&mon_icon_lock); return pending;
}
void mon_icons_wait(void) {
    ULONGLONG until = GetTickCount64() + 1500;
    while (mon_icons_pending() && GetTickCount64() < until) Sleep(10);
}
void mon_icons_close(void) {
    if (!mon_icon_started) return;
    EnterCriticalSection(&mon_icon_lock); mon_icon_stopping = true; LeaveCriticalSection(&mon_icon_lock); SetEvent(mon_icon_event);
    // Slow executable I/O must not hold up application shutdown.
    if (WaitForSingleObject(mon_icon_thread, 1000) != WAIT_OBJECT_0) return;
    CloseHandle(mon_icon_thread); CloseHandle(mon_icon_event);
    for (int i = 0; i < 64; ++i) { mg_image_free(mon_icons[i].image); free(mon_icons[i].rgba); memset(&mon_icons[i], 0, sizeof mon_icons[i]); }
    memset(mon_icon_pids, 0, sizeof mon_icon_pids); DeleteCriticalSection(&mon_icon_lock);
    mon_icon_started = mon_icon_stopping = false;
}
