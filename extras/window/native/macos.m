#import <Cocoa/Cocoa.h>
#include <math.h>
#include "../../../native/backend.h"
#include "../../../native/macos/window.h"

static struct {
    NSWindow *window;
    NSWindowStyleMask style;
    NSWindowTitleVisibility title;
    NSSize minimum;
    bool enabled, overflow, transparent;
    NSRect drag, clients[32]; int count;
} frame;
static bool frame_prepared;

static bool frame_hit(NSPoint point) {
    if (!frame.enabled || frame.overflow || !NSPointInRect(point, frame.drag)) return false;
    for (int i=0;i<frame.count;i++) if (NSPointInRect(point,frame.clients[i])) return false;
    return true;
}
static bool frame_mouse(void *event) {
    NSEvent *e=event;
    NSPoint point=[frame.window.contentView convertPoint:e.locationInWindow fromView:nil];
    if (!frame_hit(point)) return false;
    mg_macos_dismiss_focus();
    if (e.clickCount==2) {
        NSString *action=[[NSUserDefaults standardUserDefaults] stringForKey:@"AppleActionOnDoubleClick"];
        if ([action isEqualToString:@"Minimize"]) [frame.window miniaturize:nil];
        else if (![action isEqualToString:@"None"]) [frame.window zoom:nil];
    } else { [frame.window performWindowDragWithEvent:e]; }
    return true;
}
bool mg_window_native_controls(void) { return true; }
void mg_window_prepare(void) { frame_prepared=true; mg_macos_defer_show(); }
bool mg_window_frame(bool enabled,float minimum_width,float minimum_height) {
    NSWindow *window=mg_macos_window();
    bool show=frame_prepared; frame_prepared=false;
    mg_macos_mouse_hook(NULL);
    if (frame.window && frame.window==window) {
        [window setStyleMask:frame.style]; [window setTitleVisibility:frame.title];
        [window setTitlebarAppearsTransparent:frame.transparent]; [window setContentMinSize:frame.minimum];
    }
    memset(&frame,0,sizeof frame);
    const char *style=getenv("MYGOOSE_WINDOW_STYLE");
    if (style && !strcmp(style,"standard")) enabled=false;
    frame.enabled=enabled;
    if (enabled && window) {
        frame.window=window; frame.style=window.styleMask; frame.title=window.titleVisibility;
        frame.transparent=window.titlebarAppearsTransparent; frame.minimum=window.contentMinSize;
        NSRect bounds=window.frame;
        [window setStyleMask:window.styleMask|NSWindowStyleMaskFullSizeContentView];
        [window setTitleVisibility:NSWindowTitleHidden]; [window setTitlebarAppearsTransparent:YES];
        [window setContentMinSize:NSMakeSize(fmax(100,minimum_width),fmax(100,minimum_height))];
        [window setFrame:bounds display:NO];
        mg_macos_mouse_hook(frame_mouse);
    }
    if (show && window && !getenv("MYGOOSE_HIDDEN")) { [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    return frame.enabled;
}
int32_t mg_window_state(void) { return frame.window.zoomed ? 1 : 0; }
bool mg_window_command(int32_t command) {
    if (!frame.window) return false;
    if (command==0) [frame.window miniaturize:nil];
    else if (command==1) [frame.window zoom:nil];
    else if (command==2) [frame.window performClose:nil];
    else return false;
    return true;
}
void mg_window_region(int32_t kind,float x,float y,float w,float h) {
    if (kind==0) { frame.count=0; frame.overflow=false; frame.drag=NSZeroRect; return; }
    if (!isfinite(x)||!isfinite(y)||!isfinite(w)||!isfinite(h)||w<0||h<0) return;
    if (kind==1) frame.drag=NSMakeRect(x,y,w,h);
    if (kind==2) { if (frame.count<32) frame.clients[frame.count++]=NSMakeRect(x,y,w,h); else frame.overflow=true; }
}
