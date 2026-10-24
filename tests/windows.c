/* Exercise a real hidden HWND and the native message loop, not a mock. */
#include "../native/windows/platform.c"
#include <assert.h>
#include "resize_windows.h"
static void damage_scene(uint32_t background) {
    mg_clip(0,0,320,240); mg_rect(0,0,320,240,0,background);
    mg_shadow(20.25f,24.75f,260.5f,150.25f,9,8,0,3,4,0,0.35f);
    mg_rect(20.25f,24.75f,260.5f,150.25f,9,0x354a63);
    mg_text((mg_string){(const uint8_t *)"Sparse text and overlap",23},35,45,17,false,0xffffff);
    mg_clip(83.25f,47.75f,142.5f,110.25f);
    mg_rect(60,65,210,80,13,0xd18b43);
}
static void damage_region_cases(void) {
    assert(mg_open((mg_string){(const uint8_t *)"Damage",6},320,240,true));
    const float scales[] = {1.0f,1.5f,2.0f};
    for (int s=0;s<3;s++) {
        mg.scale=scales[s]; mg_buffer(px(320),px(240));
        size_t bytes=(size_t)mg.width*mg.height*sizeof(uint32_t);
        uint32_t *reference=malloc(bytes),*before=malloc(bytes); assert(reference && before);
        mg_paint_begin(0,0,320,240,0x632412); damage_scene(0x632412); mg_paint_end();
        memcpy(reference,mg.pixels,bytes);
        mg_paint_begin(0,0,320,240,0x152236); damage_scene(0x152236); mg_paint_end();
        memcpy(before,mg.pixels,bytes);
        mg_rect_region regions[MG_MAX_DAMAGE];
        for (int i=0;i<MG_MAX_DAMAGE;i++)
            regions[i]=(mg_rect_region){(i%4)*85.25f-4.3f,(i/4)*65.25f+0.4f,27.35f,43.65f};
        regions[1]=(mg_rect_region){8.5f,9.25f,27.35f,43.65f};
        assert(mg_paint_regions((mg_regions){regions,MG_MAX_DAMAGE},0x632412));
        damage_scene(0x632412); mg_paint_end();
        for (int y=0;y<mg.height;y++) for (int x=0;x<mg.width;x++) {
            bool inside=false;
            for (int i=0;i<MG_MAX_DAMAGE;i++) {
                mg_rect_region r=regions[i];
                if (x>=px(r.x) && x<edge(r.x+r.w) && y>=px(r.y) && y<edge(r.y+r.h)) { inside=true; break; }
            }
            size_t p=(size_t)y*mg.width+x;
            assert((mg.pixels[p]&0xffffff)==((inside ? reference[p] : before[p])&0xffffff));
        }
        // Dense updates fall back, and the preceding sparse DC clip is gone.
        mg_rect_region dense[]={{0,0,160,240},{160,0,160,240}};
        assert(!mg_paint_regions((mg_regions){dense,2},0x632412));
        damage_scene(0x632412); mg_paint_end();
        for (size_t p=0;p<bytes/sizeof(uint32_t);p++) assert((mg.pixels[p]&0xffffff)==(reference[p]&0xffffff));
        free(reference); free(before);
    }
    mg_close();
    puts("PASS: sparse Direct2D damage, overlap union, preserved gaps, child clips, alpha/text and 1x/1.5x/2x pixels");
}
static int next_input(int expected) {
    for (int i = 0; i < 100; i++) {
        int event = mg_wait(20);
        if (event == expected) return event;
    }
    return -1;
}
static void wheel_cases(void) {
    POINT p = {24,32}; ClientToScreen(mg.window,&p);
    PostMessageW(mg.window,WM_MOUSEWHEEL,MAKEWPARAM(0,-WHEEL_DELTA),MAKELPARAM(p.x,p.y));
    assert(next_input(4)==4 && !mg_event_scroll_pixels() && mg_event_scroll_smooth());
    assert(mg.delta==-1.0f); // Input stays intact; controls animate destinations.
    assert(mg.x==24.0f/mg.scale && mg.y==32.0f/mg.scale);
    mg_scroll_animation(true);
    int64_t next = mg.scroll_next_ns;
    mg.scroll_next_ns = mg_clock_ns()+1000000000;
    assert(mg_wait(1)==9); // A short caller deadline still wins.
    mg.scroll_next_ns = next;
    for (int i=0;i<5;i++) {
        assert(mg_wait(0)==MG_EVENT_SCROLL);
        assert(mg.delta==0.0f && !mg_event_scroll_smooth());
        assert(mg.x==24.0f/mg.scale && mg.y==32.0f/mg.scale);
    }
    mg.scroll_next_ns = mg_clock_ns()-1;
    PostMessageW(mg.window,WM_KEYDOWN,VK_RIGHT,0);
    assert(mg_wait(0)==5); // A late animation cannot starve queued input.
    mg_scroll_animation(false);
    assert(mg_wait(2)==9); // No animation wakes once the control finishes.
    PostMessageW(mg.window,WM_MOUSEWHEEL,MAKEWPARAM(0,-30),MAKELPARAM(p.x,p.y));
    assert(next_input(4)==4 && mg.delta==-0.25f && !mg_event_scroll_smooth());
    puts("PASS: intact coarse/fractional wheel input, separate animation wakes, deadlines and idle cancellation");
}
int main(void) {
    mg_string not_owned = {(const uint8_t *)"not owned", 9};
    assert(!mg_clipboard_set(not_owned)); // No HWND: fail without touching the OS clipboard.
    damage_region_cases();
    _putenv_s("MYGOOSE_HIDDEN", "1");
    mg_string title = {(const uint8_t *)"Backend test", 12};
    _putenv_s("MYGOOSE_RENDERER", "gdi");
    assert(!mg_open(title, 200, 150, false) && !mg.dc);
    _putenv_s("MYGOOSE_RENDERER", "d2d");
    assert(mg_open(title, 200, 150, false));
    assert(!mg_open(title, 200, 150, false));
    assert(mg.window && IsWindow(mg.window));
    assert(mg.width > 0 && mg.height > 0);
    resize_buffer_cases(); resize_modal_cases();
    wheel_cases();
    HCURSOR previous_pointer = GetCursor();
    mg_cursor(1); assert(mg.pointer == LoadCursor(NULL, IDC_SIZEWE));
    assert(SendMessageW(mg.window, WM_SETCURSOR, (WPARAM)mg.window, MAKELPARAM(HTCLIENT, WM_MOUSEMOVE)) == TRUE);
    assert(GetCursor() == mg.pointer);
    mg_cursor(2); assert(mg.pointer == LoadCursor(NULL, IDC_IBEAM));
    assert(SendMessageW(mg.window, WM_SETCURSOR, (WPARAM)mg.window, MAKELPARAM(HTCLIENT, WM_MOUSEMOVE)) == TRUE);
    assert(GetCursor() == mg.pointer);
    // Custom client cursors must not mask the window's native resize edges.
    SendMessageW(mg.window, WM_SETCURSOR, (WPARAM)mg.window, MAKELPARAM(HTTOP, WM_MOUSEMOVE));
    assert(GetCursor() == LoadCursor(NULL, IDC_SIZENS));
    mg_cursor(0); assert(mg.pointer == NULL);
    SendMessageW(mg.window, WM_SETCURSOR, (WPARAM)mg.window, MAKELPARAM(HTCLIENT, WM_MOUSEMOVE));
    assert(GetCursor() == LoadCursor(NULL, IDC_ARROW)); SetCursor(previous_pointer);
    PostMessageW(mg.window, WM_MOUSEMOVE, 0, MAKELPARAM(20, 30));
    assert(next_input(1) == 1); assert(mg.x == 20.0f/mg.scale && mg.y == 30.0f/mg.scale);
    PostMessageW(mg.window, WM_RBUTTONUP, 0, MAKELPARAM(24, 32)); assert(next_input(14) == 14);
    assert(mg.x == 24.0f/mg.scale && mg.y == 32.0f/mg.scale);
    PostMessageW(mg.window, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(20, 30)); assert(next_input(2) == 2);
    assert(GetCapture() == mg.window);
    mg.event = 0; assert(mg_capture(false)); assert(GetCapture() != mg.window && mg.event == 0);
    assert(mg_capture(true)); assert(GetCapture() == mg.window);
    // Simulate another native owner taking capture. This is distinct from blur.
    ReleaseCapture(); assert(mg.event == 13);
    assert(mg_capture(true));
    PostMessageW(mg.window, WM_LBUTTONUP, 0, MAKELPARAM(20, 30)); assert(next_input(3) == 3);
    assert(GetCapture() != mg.window);
    // An OS interaction can capture the same HWND without owning a UI drag.
    SetCapture(mg.window); mg.event = 0;
    assert(mg_capture(false) && GetCapture()==mg.window);
    ReleaseCapture(); assert(!mg.client_capture && mg.event==0);
    PostMessageW(mg.window, WM_KEYDOWN, VK_RIGHT, 0); assert(next_input(5) == 5); assert(mg.code == VK_RIGHT);
    PostMessageW(mg.window, WM_CHAR, 0xd83d, 0); PostMessageW(mg.window, WM_CHAR, 0xde80, 0);
    assert(next_input(6) == 6); assert(mg.code == 0x1f680);
    mg_paint_begin(0, 0, 100, 100, 0x123456); mg_paint_end();
    assert((mg.pixels[0] & 0xffffff) == 0x123456);
    // IMM cursor/attribute offsets use UTF-16; Goose needs UTF-8 byte offsets.
    WCHAR composition[4] = {L'A', 0x65e5, 0xd83d, 0xde80};
    BYTE attributes[4] = {ATTR_INPUT, ATTR_TARGET_CONVERTED, ATTR_TARGET_CONVERTED, ATTR_TARGET_CONVERTED};
    ime_decode(composition, 4, 4, attributes, 4);
    assert(ime.length == 8 && ime.cursor == 8 && ime.target_start == 1 && ime.target_end == 8);
    assert(memcmp(ime.text, "A\xe6\x97\xa5\xf0\x9f\x9a\x80", 8) == 0);
    uint8_t clipboard[8];
    assert(clipboard_decode(composition, 4, (mg_bytes){clipboard,8}) == 8);
    assert(memcmp(clipboard, "A\xe6\x97\xa5\xf0\x9f\x9a\x80", 8) == 0);
    assert(clipboard_decode(composition, 4, (mg_bytes){clipboard,7}) == -1);
    WCHAR encoded[16]; mg_string newlines = {(const uint8_t *)"a\nb\r\nc\r", 7};
    assert(clipboard_encode(newlines, encoded, 16) == 9);
    assert(wcscmp(encoded, L"a\r\nb\r\nc\r\n") == 0);
    assert(clipboard_decode(encoded, 9, (mg_bytes){clipboard,6}) == 6);
    assert(memcmp(clipboard, "a\nb\nc\n", 6) == 0);
    ime_decode(composition, 4, 3, attributes, 4); assert(ime.cursor == 4); // no split surrogate
    float old_scale = mg.scale; mg.scale = 1.5f;
    mg_ime_anchor(42, 10.5f, 20.25f, 1.0f, 19.6f, 14.0f);
    assert(ime.caret.left == 15 && ime.caret.top == 30 && ime.caret.bottom == 60);
    HIMC input = ImmGetContext(mg.window);
    if (input) {
        CANDIDATEFORM candidate; memset(&candidate, 0, sizeof(candidate));
        assert(ImmGetCandidateWindow(input, 0, &candidate));
        assert(candidate.dwStyle == CFS_EXCLUDE && candidate.ptCurrentPos.y == 60);
        assert(candidate.rcArea.left == 15 && candidate.rcArea.top == 30);
        ImmReleaseContext(mg.window, input);
    }
    SendMessageW(mg.window, WM_IME_STARTCOMPOSITION, 0, 0); assert(mg.event == 10 && ime.composing);
    mg.event = 0; SendMessageW(mg.window, WM_KEYDOWN, VK_BACK, 0); assert(mg.event == 0);
    SendMessageW(mg.window, WM_IME_ENDCOMPOSITION, 0, 0); assert(mg.event == 12 && !ime.composing);
    mg_ime_anchor(0,0,0,1,1,14); assert(ImmGetContext(mg.window) == NULL);
    mg.scale = old_scale;
    uint64_t before = mg_pixel_hash();
    mg_paint_begin(10, 10, 10, 10, 0xabcdef); mg_paint_end(); assert(mg_pixel_hash() != before);
    assert((mg.pixels[0] & 0xffffff) == 0x123456);
    mg_buffer(320, 240); assert(mg.width == 320 && mg.height == 240);
    SendMessageW(mg.window, WM_CLOSE, 0, 0); assert(mg_wait(20) == -1); mg_close();
    // Lifecycle cleanup must allow another window/headless context.
    assert(mg_open(title, 32, 32, true)); assert(mg.window == NULL); mg_cursor(1); assert(mg.pointer == NULL); mg_close();
    assert(mg_open(title, 200, 150, false)); resize_close_case();
    /* Embedders that already use fibers retain their original caller fiber. */
    void *host = ConvertThreadToFiberEx(NULL,FIBER_FLAG_FLOAT_SWITCH); assert(host);
    assert(mg_open(title,200,150,false)); assert(mg_wait(1)>=0); mg_close();
    assert(IsThreadAFiber() && GetCurrentFiber()==host); assert(ConvertFiberToThread());
    puts("PASS: HWND events, owned capture/release/loss, Unicode, IME UTF-16 offsets/candidate anchor at 150% DPI, opaque retained resize buffers, live modal resize/timer, close/unwind and fiber lifecycle");
    return 0;
}
