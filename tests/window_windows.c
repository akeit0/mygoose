/* Exercise custom framing on an owned hidden HWND, including native commands. */
#include "../native/windows/platform.c"
#include "../extras/window/native/windows.c"
#include <assert.h>
#include "resize_windows.h"
static WNDPROC test_frame_proc;
static WNDPROC observed_previous;
static int metadata_calls, activation_calls, show_calls;
static unsigned system_commands;
static LRESULT CALLBACK observe_caption(HWND window, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_SETTEXT || message == WM_SETICON || message == WM_THEMECHANGED ||
        message == WM_SYSCOLORCHANGE || message == WM_SETTINGCHANGE ||
        message == WM_ACTIVATE || message == WM_ACTIVATEAPP || message == WM_NCACTIVATE) {
        LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
        assert(!(style & WS_VISIBLE)); /* Default procedure cannot paint a caption. */
        assert((style & WS_CAPTION) == WS_CAPTION); /* Animation semantics stay intact. */
        metadata_calls++;
    }
    if (message == WM_NCACTIVATE) { assert(l == -1); activation_calls++; }
    if (message == WM_SHOWWINDOW) show_calls++;
    if (message == WM_SETCURSOR && LOWORD(l) == HTCAPTION) assert(!"caption cursor must not reach default painting");
    assert(message != WM_NCPAINT && message != MG_WM_NCUAHDRAWCAPTION && message != MG_WM_NCUAHDRAWFRAME);
    return CallWindowProcW(observed_previous, window, message, w, l);
}
static void caption_repaint_cases(void) {
    /* Exercise both hidden and visible-style paths off screen, without showing
       a test window or changing desktop animation/accessibility settings. */
    LONG_PTR original = GetWindowLongPtrW(mg.window, GWL_STYLE);
    observed_previous = frame.previous; frame.previous = observe_caption;
    RECT position; GetWindowRect(mg.window, &position);
    SetWindowPos(mg.window,NULL,-32000,-32000,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    for (int visible = 0; visible < 2; visible++) {
        LONG_PTR style = GetWindowLongPtrW(mg.window,GWL_STYLE);
        SetWindowLongPtrW(mg.window,GWL_STYLE,visible ? style|WS_VISIBLE : style&~((LONG_PTR)WS_VISIBLE));
        metadata_calls = activation_calls = show_calls = 0;
        assert(SetWindowTextW(mg.window,L"日本語 custom title"));
        WCHAR text[64]; assert(GetWindowTextW(mg.window,text,64)>0 && !wcscmp(text,L"日本語 custom title"));
        HICON icon=LoadIcon(NULL,IDI_APPLICATION);
        HICON old=(HICON)SendMessageW(mg.window,WM_SETICON,ICON_SMALL,(LPARAM)icon);
        assert((HICON)SendMessageW(mg.window,WM_GETICON,ICON_SMALL,0)==icon);
        SendMessageW(mg.window,WM_SETICON,ICON_SMALL,(LPARAM)old);
        SendMessageW(mg.window,WM_NCACTIVATE,FALSE,0);
        SendMessageW(mg.window,WM_NCACTIVATE,TRUE,0);
        SendMessageW(mg.window,WM_ACTIVATE,WA_INACTIVE,0);
        SendMessageW(mg.window,WM_ACTIVATEAPP,FALSE,0);
        SendMessageW(mg.window,WM_ACTIVATE,WA_ACTIVE,0);
        SendMessageW(mg.window,WM_ACTIVATEAPP,TRUE,0);
        SendMessageW(mg.window,WM_THEMECHANGED,0,0);
        SendMessageW(mg.window,WM_SYSCOLORCHANGE,0,0);
        SendMessageW(mg.window,WM_SETTINGCHANGE,SPI_SETNONCLIENTMETRICS,0);
        SendMessageW(mg.window,WM_NCPAINT,1,0);
        SendMessageW(mg.window,MG_WM_NCUAHDRAWCAPTION,0,0);
        SendMessageW(mg.window,MG_WM_NCUAHDRAWFRAME,0,0);
        assert(SendMessageW(mg.window,WM_SETCURSOR,(WPARAM)mg.window,MAKELPARAM(HTCAPTION,WM_MOUSEMOVE))==TRUE);
        assert(metadata_calls >= 6 && activation_calls >= 2);
        assert(show_calls == 0); /* Metadata updates cannot flash a window. */
        assert(!!(GetWindowLongPtrW(mg.window,GWL_STYLE)&WS_VISIBLE)==visible);
        assert((GetWindowLongPtrW(mg.window,GWL_STYLE)&WS_CAPTION)==WS_CAPTION);
        RECT client,outer; GetClientRect(mg.window,&client); GetWindowRect(mg.window,&outer);
        assert(client.right==outer.right-outer.left && client.bottom==outer.bottom-outer.top);
    }
    SetWindowLongPtrW(mg.window,GWL_STYLE,original);
    frame.previous = observed_previous;
    SetWindowPos(mg.window,NULL,position.left,position.top,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    assert(!IsWindowVisible(mg.window));
}
static LRESULT CALLBACK never_show(HWND window, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_SYSCOMMAND) {
        unsigned command = (unsigned)w & 0xfff0;
        if (command == SC_MINIMIZE || command == SC_MAXIMIZE || command == SC_RESTORE) {
            assert((GetWindowLongPtrW(window,GWL_STYLE)&WS_CAPTION)==WS_CAPTION);
            system_commands |= command == SC_MINIMIZE ? 1u : command == SC_MAXIMIZE ? 2u : 4u;
        }
    }
    if (message == WM_WINDOWPOSCHANGING) ((WINDOWPOS *)l)->flags &= ~SWP_SHOWWINDOW;
    return CallWindowProcW(test_frame_proc, window, message, w, l);
}
static void pump(void) {
    for (int i = 0; i < 4; ++i) if (mg_wait(5) < 0) break;
}
static LRESULT hit(int x, int y) {
    POINT p = {x,y}; ClientToScreen(mg.window, &p);
    return SendMessageW(mg.window, WM_NCHITTEST, 0, MAKELPARAM(p.x,p.y));
}
static void regions(void) {
    mg_window_region(0,0,0,0,0); mg_window_region(1,0,0,800,58); mg_window_region(2,300,0,100,34);
}
static void caption_focus_case(mg_string title) {
    assert(mg_open(title,800,600,false)); assert(mg_window_frame(true,320,200)); regions();
    HWND focused = GetFocus(); POINT point = {100,20}; ClientToScreen(mg.window,&point);
    assert(PostMessageW(mg.window,WM_NCLBUTTONDOWN,HTCAPTION,MAKELPARAM(point.x,point.y)));
    bool delivered = false;
    for (int i = 0; i < 32 && !delivered; ++i) delivered = mg_wait(30) == 7 && mg.dispatching;
    /* Delivered before native moving starts, even when the app is paused.
       The window stays focused; only the Goose control focus is dismissed. */
    assert(delivered && !mg.sizing && GetFocus() == focused && !IsWindowVisible(mg.window));
    /* Closing while suspended must not subsequently enter a native move loop. */
    mg_close(); assert(!frame.window && !mg.dispatch_fiber && !mg.caller_fiber && !IsThreadAFiber());
}
int main(void) {
    mg_string title = {(const uint8_t *)"Custom frame test",17};
    _putenv_s("MYGOOSE_HIDDEN", "");
    mg_window_prepare(); assert(mg_open(title,800,600,false));
    assert(!IsWindowVisible(mg.window)); /* Deferred showing before attaching. */
    _putenv_s("MYGOOSE_HIDDEN", "1");
    RECT before; GetClientRect(mg.window, &before);
    assert(mg_window_frame(true,320,200));
    RECT client, outer; GetClientRect(mg.window,&client); GetWindowRect(mg.window,&outer);
    assert(client.right == before.right && client.bottom == before.bottom);
    assert(client.right == outer.right-outer.left && client.bottom == outer.bottom-outer.top);
    assert(!IsWindowVisible(mg.window));
    LONG_PTR style = GetWindowLongPtrW(mg.window,GWL_STYLE);
    assert((style & WS_CAPTION)==WS_CAPTION); /* Native minimize/restore animation eligibility. */
    assert((style & WS_THICKFRAME) && (style & WS_MAXIMIZEBOX) && (style & WS_SYSMENU));
    caption_repaint_cases(); resize_buffer_cases(); resize_modal_cases();
    enum DWMNCRENDERINGPOLICY policy=DWMNCRP_DISABLED;
    DwmSetWindowAttribute(mg.window,DWMWA_NCRENDERING_POLICY,&policy,sizeof policy);
    caption_repaint_cases(); /* Classic drawing paths must stay suppressed too. */
    SendMessageW(mg.window,WM_NCACTIVATE,FALSE,0);
    SendMessageW(mg.window,WM_NCACTIVATE,TRUE,0);
    SendMessageW(mg.window,WM_THEMECHANGED,0,0);
    SendMessageW(mg.window,WM_DWMCOMPOSITIONCHANGED,0,0);
    RedrawWindow(mg.window,NULL,NULL,RDW_FRAME|RDW_INVALIDATE|RDW_UPDATENOW);
    GetClientRect(mg.window,&client); GetWindowRect(mg.window,&outer);
    assert((GetWindowLongPtrW(mg.window,GWL_STYLE)&WS_CAPTION)==WS_CAPTION);
    assert(client.right==outer.right-outer.left && client.bottom==outer.bottom-outer.top);
    policy=DWMNCRP_USEWINDOWSTYLE;
    DwmSetWindowAttribute(mg.window,DWMWA_NCRENDERING_POLICY,&policy,sizeof policy);
    regions(); float scale = frame_scale(mg.window);
    assert(hit((int)(100*scale),(int)(20*scale)) == HTCAPTION);
    assert(hit((int)(350*scale),(int)(20*scale)) == HTCLIENT);
    assert(hit((int)(100*scale),(int)(80*scale)) == HTCLIENT);
    assert(hit(1,1)==HTTOPLEFT && hit(client.right-1,1)==HTTOPRIGHT);
    assert(hit(1,client.bottom-1)==HTBOTTOMLEFT && hit(client.right-1,client.bottom-1)==HTBOTTOMRIGHT);
    assert(hit(1,client.bottom/2)==HTLEFT && hit(client.right-1,client.bottom/2)==HTRIGHT);
    assert(hit(client.right/2,1)==HTTOP && hit(client.right/2,client.bottom-1)==HTBOTTOM);
    assert(frame_hit_at(1200,900,(POINT){150,30},1.5f,false)==HTCAPTION);
    assert(frame_hit_at(1200,900,(POINT){525,30},1.5f,false)==HTCLIENT);
    assert(frame_hit_at(1200,900,(POINT){8,200},1.5f,false)==HTLEFT);
    assert(frame_hit_at(1200,900,(POINT){10,200},1.5f,false)==HTCLIENT);
    assert(frame_hit_at(1200,900,(POINT){1,1},1.5f,true)==HTCAPTION);
    SetWindowPos(mg.window,NULL,-400,-200,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    assert(hit((int)(100*scale),(int)(20*scale))==HTCAPTION); /* Signed screen coordinates. */
    for (int i=0;i<33;i++) mg_window_region(2,600,0,10,10);
    assert(hit((int)(100*scale),(int)(20*scale))==HTCLIENT); regions();
    assert(!mg_window_frame(false,320,200));
    assert((GetWindowLongPtrW(mg.window,GWL_STYLE)&WS_CAPTION)==WS_CAPTION);
    GetClientRect(mg.window,&client); assert(client.right==before.right && client.bottom==before.bottom);
    assert(mg_window_frame(true,320,200)); regions();
    /* Prevent native maximize/minimize from showing a test window. */
    test_frame_proc=(WNDPROC)SetWindowLongPtrW(mg.window,GWLP_WNDPROC,(LONG_PTR)never_show);
    assert(mg_window_command(1)); pump(); assert(IsZoomed(mg.window) && mg_window_state()==1);
    assert(!IsWindowVisible(mg.window));
    MONITORINFO monitor={.cbSize=sizeof monitor}; assert(GetMonitorInfoW(MonitorFromWindow(mg.window,MONITOR_DEFAULTTONEAREST),&monitor));
    GetWindowRect(mg.window,&outer); GetClientRect(mg.window,&client);
    POINT origin={0,0}; ClientToScreen(mg.window,&origin);
    assert(origin.x==monitor.rcWork.left && origin.y==monitor.rcWork.top);
    assert(client.right==monitor.rcWork.right-monitor.rcWork.left && client.bottom==monitor.rcWork.bottom-monitor.rcWork.top);
    assert(mg_window_command(1)); pump(); assert(!IsZoomed(mg.window) && mg_window_state()==0);
    assert(mg_window_command(0)); pump(); assert(IsIconic(mg.window));
    assert(mg_window_command(1)); pump(); assert(!IsIconic(mg.window));
    caption_repaint_cases(); /* Restoring must not lose the paint guards or styles. */
    SendMessageW(mg.window,WM_NCLBUTTONDBLCLK,HTCAPTION,0); pump(); assert(IsZoomed(mg.window));
    assert(system_commands==7); /* All three actions use the native command path. */
    assert(GetSystemMenu(mg.window,FALSE)); assert(!mg_window_command(99));
    assert(mg_window_command(2)); assert(mg_wait(100)==-1); assert(!frame.window); mg_close();
    assert(mg_open(title,32,32,true)); assert(mg_window_frame(true,320,200));
    assert(!mg_window_command(2)); mg_window_frame(false,320,200); mg_close();
    assert(mg_open(title,800,600,false)); assert(GetWindowLongPtrW(mg.window,GWLP_WNDPROC)==(LONG_PTR)mg_proc);
    /* Attaching to an initially captionless host adds animation semantics,
       then restores that host's original style and client size on detach. */
    SetWindowLongPtrW(mg.window,GWL_STYLE,GetWindowLongPtrW(mg.window,GWL_STYLE)&~((LONG_PTR)WS_CAPTION));
    SetWindowPos(mg.window,NULL,0,0,0,0,SWP_FRAMECHANGED|SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    GetClientRect(mg.window,&before);
    assert(mg_window_frame(true,320,200)); assert((GetWindowLongPtrW(mg.window,GWL_STYLE)&WS_CAPTION)==WS_CAPTION);
    assert(!mg_window_frame(false,320,200)); assert(!(GetWindowLongPtrW(mg.window,GWL_STYLE)&WS_CAPTION));
    GetClientRect(mg.window,&client); assert(EqualRect(&before,&client)); mg_close();
    assert(mg_open(title,800,600,false)); assert(mg_window_frame(true,320,200));
    resize_close_case(); assert(!frame.window);
    caption_focus_case(title);
    puts("PASS: native animation styles, hidden caption/metadata/theme/activation paint guards, deferred show, DPI/signed hit tests, resize edges, control exclusions, work-area maximize, restore/minimize/close, double-click and lifecycle");
    return 0;
}
