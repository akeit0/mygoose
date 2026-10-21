/* Shared regression fixture for standard and custom-framed owned HWNDs.
   A bounded nested message loop models User32's modal resize dispatch without
   driving the desktop mouse, showing a window, or changing system settings. */
static struct {
    WNDPROC previous;
    bool inside, done, resizing;
    int ticks, completed;
} resize_case;
#define TEST_RESIZE_MODAL (WM_APP+42)
static LRESULT CALLBACK resize_case_proc(HWND window, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_TIMER && w == MG_RESIZE_TIMER) resize_case.ticks++;
    if (message == WM_WINDOWPOSCHANGING && resize_case.resizing) {
        LRESULT result = CallWindowProcW(resize_case.previous,window,message,w,l);
        assert(((WINDOWPOS *)l)->flags & SWP_NOCOPYBITS);
        return result;
    }
    if (message != TEST_RESIZE_MODAL) return CallWindowProcW(resize_case.previous,window,message,w,l);
    resize_case.inside = true;
    /* User32 holds capture during a native edge drag. Goose cancels its own
       interactions on each resize; that must not release User32's capture. */
    assert(mg_capture(true)); assert(GetCapture()==window);
    SendMessageW(window,WM_ENTERSIZEMOVE,0,0);
    const int widths[3] = {430,560,390}, heights[3] = {300,390,270};
    RECT origin; GetWindowRect(window,&origin);
    for (int i = 0; i < 3 && IsWindow(window); i++) {
        RECT rect = {0,0,widths[i],heights[i]};
        AdjustWindowRectEx(&rect,(DWORD)GetWindowLongPtrW(window,GWL_STYLE),FALSE,(DWORD)GetWindowLongPtrW(window,GWL_EXSTYLE));
        resize_case.resizing = true;
        /* Include top/left movement, where saved client bits are most visible. */
        SetWindowPos(window,NULL,origin.left+i*7,origin.top+i*5,rect.right-rect.left,rect.bottom-rect.top,SWP_NOZORDER|SWP_NOACTIVATE);
        resize_case.resizing = false; resize_case.completed++;
        /* Keep dispatching while the edge is held stationary. The resize
           timer must return control to Goose before this loop has finished. */
        ULONGLONG deadline = GetTickCount64()+1000;
        while (i == 0 && IsWindow(window) && resize_case.ticks < 2 && GetTickCount64() < deadline) {
            if (MsgWaitForMultipleObjectsEx(0,NULL,30,QS_ALLINPUT,MWMO_INPUTAVAILABLE)==WAIT_FAILED) break;
            MSG msg;
            if (PeekMessageW(&msg,NULL,0,0,PM_REMOVE)) {
                if (msg.message == WM_QUIT) break;
                TranslateMessage(&msg); DispatchMessageW(&msg);
            }
        }
    }
    if (IsWindow(window)) {
        assert(GetCapture()==window);
        ReleaseCapture(); SendMessageW(window,WM_EXITSIZEMOVE,0,0);
    }
    resize_case.inside = false; resize_case.done = true; return 0;
}
static void resize_buffer_cases(void) {
    RECT client; GetClientRect(mg.window,&client);
    mg_buffer(80,60);
    mg_paint_begin(0,0,80,60,0x132435); mg_rect(8,8,20,20,0,0xe02143); mg_paint_end();
    mg_buffer(140,100);
    assert(mg.pixels[10*140+10]==0xffe02143u);
    assert(mg.pixels[90*140+130]==0xff132435u);
    for (int i = 0; i < 140*100; i++) assert((mg.pixels[i]>>24)==255);
    /* WM_PAINT / WM_ERASEBKGND before WM_SIZE must cover areas larger than the
       bitmap, with opaque pixels. Capture the presentation into an owned DIB. */
    HDC dc = CreateCompatibleDC(NULL); assert(dc);
    BITMAPINFO info = {.bmiHeader = {.biSize=sizeof(BITMAPINFOHEADER),.biWidth=160,.biHeight=-120,
        .biPlanes=1,.biBitCount=32,.biCompression=BI_RGB}};
    uint32_t *pixels = NULL;
    HBITMAP bitmap = CreateDIBSection(dc,&info,DIB_RGB_COLORS,(void **)&pixels,NULL,0); assert(bitmap && pixels);
    HBITMAP old = SelectObject(dc,bitmap);
    memset(pixels,0,160*120*4);
    assert(SendMessageW(mg.window,WM_ERASEBKGND,(WPARAM)dc,0)==1); GdiFlush();
    assert(pixels[10*160+10]==0xffe02143u && pixels[119*160+159]==0xff132435u);
    for (int i = 0; i < 160*120; i++) assert((pixels[i]>>24)==255);
    SelectObject(dc,old); DeleteObject(bitmap); DeleteDC(dc);
    /* Shrink and grow to the previous render-target size without a paint in
       between. The render target must bind the replacement DIB, not stale data. */
    mg_paint_begin(0,0,140,100,0x234567); mg_paint_end();
    mg_buffer(90,70); mg_buffer(140,100);
    mg_paint_begin(0,0,140,100,0x345678); mg_paint_end();
    assert(mg.pixels[0]==0xff345678u && mg.pixels[13999]==0xff345678u);
    mg_buffer(client.right,client.bottom);
}
static void resize_install_case(void) {
    memset(&resize_case,0,sizeof resize_case);
    resize_case.previous = (WNDPROC)SetWindowLongPtrW(mg.window,GWLP_WNDPROC,(LONG_PTR)resize_case_proc);
    assert(resize_case.previous);
}
static void resize_modal_cases(void) {
    RECT original; GetWindowRect(mg.window,&original);
    resize_install_case(); assert(PostMessageW(mg.window,TEST_RESIZE_MODAL,0,0));
    int resized = 0, ticked = 0;
    DWORD thread = GetCurrentThreadId();
    for (int i = 0; i < 100 && !resize_case.done; i++) {
        int event = mg_wait(50); assert(event >= 0 && GetCurrentThreadId()==thread);
        if (resize_case.inside && event == 8) {
            assert(resize_case.resizing); resized++;
            /* Mirrors send(resize) and layout's cancel_pointer in ui.goose. */
            assert(!mg_capture(true)); /* UI cannot claim the native drag. */
            assert(mg_capture(false)); assert(GetCapture()==mg.window);
            RECT client; GetClientRect(mg.window,&client);
            assert(mg.width==client.right && mg.height==client.bottom);
        }
        if (resize_case.inside && event == 9) ticked++;
        mg_paint_begin(0,0,mg_width(),mg_height(),0x213243); mg_paint_end();
        assert(mg.pixels[(int64_t)mg.width*mg.height-1]==0xff213243u);
    }
    assert(resize_case.done && resized >= 3 && ticked >= 2 && resize_case.completed==3 && !mg.sizing);
    SetWindowLongPtrW(mg.window,GWLP_WNDPROC,(LONG_PTR)resize_case.previous);
    SetWindowPos(mg.window,NULL,original.left,original.top,original.right-original.left,original.bottom-original.top,SWP_NOZORDER|SWP_NOACTIVATE);
    assert(!IsWindowVisible(mg.window));
}
static DWORD WINAPI resize_send_modal(void *window) {
    SendMessageW(window,TEST_RESIZE_MODAL,0,0); return 0;
}
static void resize_close_case(void) {
    resize_install_case();
    /* Sent callbacks run inside PeekMessage/MsgWait rather than our explicit
       DispatchMessage. They must be unwound safely on shutdown as well. */
    HANDLE sender = CreateThread(NULL,0,resize_send_modal,mg.window,0,NULL); assert(sender);
    for (int i = 0; i < 100 && !resize_case.inside; i++) assert(mg_wait(50)>=0);
    assert(resize_case.inside && mg.dispatching);
    mg_close();
    assert(WaitForSingleObject(sender,1000)==WAIT_OBJECT_0); CloseHandle(sender);
    assert(resize_case.done && !resize_case.inside && !mg.dispatch_fiber && !mg.caller_fiber && !IsThreadAFiber());
}
