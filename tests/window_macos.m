/* Real AppKit controls, with no pointer movement or file-manager launches. */
#include "../native/macos/platform.m"
#include "../extras/window/native/macos.m"
#include <assert.h>
int main(void) {
    setenv("MYGOOSE_HIDDEN","1",1);
    mg_window_prepare();
    assert(mg_open((mg_string){(const uint8_t *)"Frame test",10},700,480,false));
    NSWindowStyleMask original=mg.window.styleMask;
    NSSize minimum=mg.window.contentMinSize;
    assert(mg_window_frame(true,600,400) && mg_window_native_controls());
    assert((mg.window.styleMask&NSWindowStyleMaskFullSizeContentView) && mg.window.titlebarAppearsTransparent);
    assert(mg.window.titleVisibility==NSWindowTitleHidden && mg.window.contentMinSize.width==600);
    for (NSWindowButton type=NSWindowCloseButton;type<=NSWindowZoomButton;type++) {
        NSButton *button=[mg.window standardWindowButton:type];
        assert(button && !button.hidden && button.enabled && button.superview);
    }
    mg_window_region(1,0,0,700,46);
    mg_window_region(2,400,5,250,36);
    assert(frame_hit(NSMakePoint(200,20)) && !frame_hit(NSMakePoint(420,20)) && !frame_hit(NSMakePoint(200,60)));
    for (int i=0;i<33;i++) mg_window_region(2,1,1,1,1);
    assert(!frame_hit(NSMakePoint(200,20))); /* Overflow never steals input. */
    mg_window_region(0,0,0,0,0); assert(!frame_hit(NSMakePoint(200,20)));
    [mg.window setContentSize:NSMakeSize(800,600)];
    [mg.delegate windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:mg.window]];
    assert(mg_width()==800 && mg_height()==600);
    assert(!mg_window_frame(false,0,0) && mg.window.styleMask==original && mg.window.contentMinSize.width==minimum.width);
    setenv("MYGOOSE_WINDOW_STYLE","standard",1);
    assert(!mg_window_frame(true,600,400) && !(mg.window.styleMask&NSWindowStyleMaskFullSizeContentView));
    unsetenv("MYGOOSE_WINDOW_STYLE");
    assert(mg_window_frame(true,600,400));
    assert(mg_window_command(2) && mg_wait(1)==-1);
    mg_window_frame(false,0,0); mg_close();
    puts("PASS: integrated AppKit title bar, native traffic lights, minimum size, resize, caption exclusions/overflow, standard style and close");
}
