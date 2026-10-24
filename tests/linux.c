/* Native X11 delivery. Run on a private Xvfb display for clipboard tests. */
#include "../native/linux/platform.c"
#include <assert.h>
static void send_input(int type, int x, int y, unsigned int detail) {
    XEvent event={0}; event.xany.type=type; event.xany.display=mg.display; event.xany.window=mg.window;
    long mask=0;
    if (type==MotionNotify) { event.xmotion.x=x; event.xmotion.y=y; mask=PointerMotionMask; }
    else if (type==KeyPress) { event.xkey.keycode=XKeysymToKeycode(mg.display,detail); mask=KeyPressMask; }
    else { event.xbutton.x=x; event.xbutton.y=y; event.xbutton.button=detail; event.xbutton.time=1000; mask=type==ButtonPress ? ButtonPressMask : ButtonReleaseMask; }
    XSendEvent(mg.display,mg.window,False,mask,&event); XFlush(mg.display);
}
static void next_input(int kind) { for (int i=0;i<100;i++) { if (mg_wait(20)==kind) return; } assert(!"Expected X11 event"); }
static void animation_tests(void) {
    while (mg_wait(1)!=9) {}
    float x=mg.x,y=mg.y;
    mg_animation_pending(true);
    int64_t next=mg.animation_next_ns; mg.animation_next_ns=mg_clock_ns()+1000000000;
    assert(mg_wait(1)==9); mg.animation_next_ns=next;
    for (int i=0;i<3;i++) {
        assert(mg_wait(0)==MG_EVENT_ANIMATION && mg.delta==0.0f && mg.x==x && mg.y==y);
    }
    mg_animation_pending(false); assert(mg_wait(2)==9);
    puts("PASS: X11 animation wakes, caller deadlines, preserved pointer/input and idle stop");
}
int main(void) {
    setenv("MYGOOSE_HIDDEN","1",1);
    mg_string title={(const uint8_t *)"X11 test",8}; assert(mg_open(title,200,150,false));
    mg_cursor(1); assert(mg.pointer_shape == 1 && mg.resize_pointer);
    Cursor cached_pointer = mg.resize_pointer; mg_cursor(0); assert(mg.pointer_shape == 0);
    mg_cursor(1); assert(mg.resize_pointer == cached_pointer); mg_cursor(0); XSync(mg.display,False);
    mg_cursor(2); assert(mg.pointer_shape == 2 && mg.text_pointer);
    Cursor cached_text = mg.text_pointer; mg_cursor(0); mg_cursor(2); assert(mg.text_pointer == cached_text); mg_cursor(0);
    if (getenv("MYGOOSE_TEST_CLIPBOARD")) {
        // The private Xvfb fixture can map a window without opening UI on WSLg.
        XMapWindow(mg.display,mg.window); XSync(mg.display,False);
        assert(mg_capture(true) && mg.captured); assert(mg_capture(true));
        assert(mg_capture(false) && !mg.captured); assert(mg_capture(false));
        XSync(mg.display,False);
        while (XPending(mg.display)) { XEvent pending; XNextEvent(mg.display,&pending); }
    }
    animation_tests();
    send_input(MotionNotify,20,30,0); next_input(1); assert(mg.x==20/mg.scale && mg.y==30/mg.scale);
    send_input(ButtonPress,20,30,1); next_input(2); assert(mg.code==1);
    send_input(ButtonRelease,20,30,1); next_input(3);
    send_input(ButtonRelease,24,32,3); next_input(14); assert(mg.x==24/mg.scale && mg.y==32/mg.scale);
    send_input(ButtonPress,20,30,1); next_input(2); assert(mg.code==2);
    send_input(ButtonRelease,20,30,1); next_input(3);
    send_input(KeyPress,0,0,XK_Right); next_input(5); assert(mg.code==39);
    mg_ime_anchor(42,20,30,1,20,14);
    send_input(KeyPress,0,0,XK_a); next_input(11); assert(mg.result_length==1 && mg.result[0]=='a');
    send_input(KeyPress,0,0,XK_Return); next_input(5); assert(mg.code==13);
    send_input(KeyPress,0,0,XK_Tab); next_input(5); assert(mg.code==9);
    send_input(KeyPress,0,0,XK_BackSpace); next_input(5); assert(mg.code==8);
    send_input(KeyPress,0,0,XK_Delete); next_input(5); assert(mg.code==46);
    wchar_t chars[2]={0x65e5,0x672c}; XIMText text={.length=2,.encoding_is_wchar=True,.string.wide_char=chars};
    XIMPreeditDrawCallbackStruct draw={.caret=2,.chg_first=0,.chg_length=0,.text=&text};
    preedit_draw(mg.ic,NULL,(XPointer)&draw); assert(mg_ime_cursor()==6 && mg.ime_length==6);
    assert(memcmp(mg.ime_text,"\xe6\x97\xa5\xe6\x9c\xac",6)==0);
    preedit_done(mg.ic,NULL,NULL); assert(mg.pending==12); mg.pending=0;
    if (getenv("MYGOOSE_TEST_CLIPBOARD")) {
        assert(mg_clipboard_set((mg_string){(const uint8_t *)"hello \xe6\x97\xa5",9}));
        Display *reader=XOpenDisplay(NULL); assert(reader);
        Window window=XCreateSimpleWindow(reader,DefaultRootWindow(reader),0,0,1,1,0,0,0);
        Atom property=XInternAtom(reader,"TEST_SELECTION",False);
        XConvertSelection(reader,mg.clipboard,mg.utf8,property,window,CurrentTime); XSync(reader,False);
        mg_wait(30); XSync(reader,False); XEvent event;
        assert(XCheckTypedWindowEvent(reader,window,SelectionNotify,&event)); assert(event.xselection.property==property);
        Atom type; int format; unsigned long count,left; unsigned char *bytes=NULL;
        assert(XGetWindowProperty(reader,window,property,0,65536,True,AnyPropertyType,&type,&format,&count,&left,&bytes)==Success);
        assert(count==9 && !left && type==mg.utf8 && format==8 && memcmp(bytes,"hello \xe6\x97\xa5",9)==0);
        XFree(bytes); XDestroyWindow(reader,window); XCloseDisplay(reader);
    }
    XResizeWindow(mg.display,mg.window,320,240); XFlush(mg.display); next_input(8); assert(mg.width==320 && mg.height==240);
    XEvent close={0}; close.xclient.type=ClientMessage; close.xclient.window=mg.window; close.xclient.format=32; close.xclient.data.l[0]=(long)mg.close;
    XSendEvent(mg.display,mg.window,False,0,&close); XFlush(mg.display); next_input(-1); mg_close();
    assert(mg_open(title,32,32,false)); assert(!mg.resize_pointer && !mg.pointer_shape); mg_close();
    puts("PASS: X11 mouse/keys, UTF-8 text, XIM preedit, clipboard protocol, resize and lifecycle");
}
