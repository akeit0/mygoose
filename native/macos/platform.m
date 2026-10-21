/* AppKit window/input, CoreGraphics CPU bitmap, CoreText shaping/fallback. */
#include "../backend.h"
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/CADisplayLink.h>
#include <mach/mach.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "window.h"
#include "context.h"
#include "../damage.h"

static bool mg_defer_show;
static bool (*mg_mouse_hook)(void *event);

@class MGView, MGDelegate;
enum { MG_LINE_CACHE = 512, MG_FONT_CACHE = 32 };
typedef struct { uint64_t hash; CTLineRef line; double width, baseline; } mg_line;
typedef struct { uint32_t size; bool bold; CTFontRef font; double baseline; } mg_font;
static struct {
    NSWindow *window; MGView *view; MGDelegate *delegate; NSAutoreleasePool *pool;
    CGContextRef bitmap; uint32_t *pixels; int width,height,event,code,mods;
    float scale,bitmap_scale,x,y,delta; CGRect dirty,caret; bool headless,closed,clipboard_valid,scroll_pixels,resize_pending;
    uint32_t background; CGRect damage[MG_MAX_DAMAGE]; int damage_count; bool damage_saved;
    mg_dispatch_stack dispatch_stack;
    bool dispatching,on_dispatch,stopping;
    int wait_timeout,wait_result; double wait_deadline;
    NSTimer *resize_timer,*wait_timer; NSInteger wait_serial;
    CADisplayLink *display_link; int display_rate,display_applied; int64_t frame_ns;
    int pointer_shape;
    uint8_t clipboard[65536]; int clipboard_length;
    mg_line lines[MG_LINE_CACHE]; unsigned next_line;
    mg_font fonts[MG_FONT_CACHE]; unsigned next_font;
    uint64_t owner; uint8_t preedit[4096],result[4096]; int length,result_length,cursor,target_start,target_end;
    NSString *marked; NSRange selected;
} mg;

static void clear_text_cache(void) {
    for (int i=0;i<MG_LINE_CACHE;i++) { if (mg.lines[i].line) CFRelease(mg.lines[i].line); mg.lines[i]=(mg_line){0}; }
    for (int i=0;i<MG_FONT_CACHE;i++) { if (mg.fonts[i].font) CFRelease(mg.fonts[i].font); mg.fonts[i]=(mg_font){0}; }
    mg.next_line=mg.next_font=0;
}
static NSString *string(mg_string text) {
    if (text.len<0 || text.len>65536) return nil;
    return [[[NSString alloc] initWithBytes:text.data length:(NSUInteger)text.len encoding:NSUTF8StringEncoding] autorelease];
}
static int utf8_prefix(NSString *s, NSUInteger index) {
    index=MIN(index,s.length);
    if (index && index<s.length && CFStringIsSurrogateLowCharacter([s characterAtIndex:index])) index--;
    return (int)[[s substringToIndex:index] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}
// Both AppKit's flipped view and the CPU bitmap use a top-left origin.
static void draw_bitmap(CGContextRef context, CGContextRef bitmap, float scale) {
    CGImageRef image=CGBitmapContextCreateImage(bitmap);
    CGFloat width=CGImageGetWidth(image)/scale, height=CGImageGetHeight(image)/scale;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context,0,height); CGContextScaleCTM(context,1,-1);
    CGContextSetBlendMode(context,kCGBlendModeCopy);
    CGContextDrawImage(context,CGRectMake(0,0,width,height),image);
    CGContextRestoreGState(context); CGImageRelease(image);
}
static void release_region(void *info,const void *data,size_t length) { (void)info; (void)length; free((void *)data); }
static CGImageRef copy_region(CGRect pixels) {
    // AppKit retains images in its display list beyond drawRect. A snapshot
    // of the entire live bitmap retains/transfers a full frame even for a
    // tiny damaged area. Give it an
    // independent, immutable copy of just the requested physical pixels.
    size_t width=(size_t)pixels.size.width,height=(size_t)pixels.size.height,stride=width*4;
    uint8_t *data=malloc(stride*height);
    if (!data) return NULL;
    CGContextFlush(mg.bitmap);
    const uint8_t *source=(const uint8_t *)mg.pixels+(size_t)pixels.origin.y*mg.width*4+(size_t)pixels.origin.x*4;
    for (size_t y=0;y<height;y++) memcpy(data+y*stride,source+y*mg.width*4,stride);
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,data,stride*height,release_region);
    if (!provider) { free(data); return NULL; }
    CGImageRef image=CGImageCreate(width,height,8,32,stride,CGBitmapContextGetColorSpace(mg.bitmap),
        kCGBitmapByteOrder32Little|kCGImageAlphaNoneSkipFirst,provider,NULL,false,kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    return image;
}
static void draw_region(CGContextRef context,CGRect rect) {
    CGFloat scale=mg.bitmap_scale;
    CGRect pixels=CGRectIntersection(CGRectIntegral(CGRectMake(rect.origin.x*scale,rect.origin.y*scale,
        rect.size.width*scale,rect.size.height*scale)),CGRectMake(0,0,mg.width,mg.height));
    if (CGRectIsEmpty(pixels) || CGRectIsNull(pixels)) return;
    // Large redraws benefit from CoreGraphics' VM-backed snapshot storage.
    // Copying those into malloc-backed images makes AppKit's image cache much
    // more expensive. Small updates are the case that needs a cropped copy.
    if (pixels.size.width*pixels.size.height>=(double)mg.width*mg.height/4) { draw_bitmap(context,mg.bitmap,scale); return; }
    CGImageRef image=copy_region(pixels);
    if (!image) { draw_bitmap(context,mg.bitmap,scale); return; }
    CGContextSaveGState(context);
    CGContextTranslateCTM(context,pixels.origin.x/scale,(pixels.origin.y+pixels.size.height)/scale); CGContextScaleCTM(context,1,-1);
    CGContextSetBlendMode(context,kCGBlendModeCopy);
    CGContextDrawImage(context,CGRectMake(0,0,pixels.size.width/scale,pixels.size.height/scale),image);
    CGContextRestoreGState(context); CGImageRelease(image);
}
static void buffer(int width,int height) {
    if (width==mg.width && height==mg.height && mg.bitmap && mg.bitmap_scale==mg.scale) return;
    if (width<1 || height<1 || width>16384 || height>16384 || (int64_t)width*height>67108864) {
        fputs("MyGoose: invalid framebuffer size\n",stderr); exit(1);
    }
    CGContextRef previous=mg.bitmap;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    mg.bitmap=CGBitmapContextCreate(NULL,width,height,8,(size_t)width*4,space,kCGBitmapByteOrder32Little|kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(space); if (!mg.bitmap) { fputs("MyGoose: cannot allocate framebuffer\n",stderr); exit(1); }
    mg.pixels=CGBitmapContextGetData(mg.bitmap); mg.width=width; mg.height=height;
    CGContextTranslateCTM(mg.bitmap,0,height); CGContextScaleCTM(mg.bitmap,mg.scale,-mg.scale);
    CGContextSetRGBFillColor(mg.bitmap,((mg.background>>16)&255)/255.0,((mg.background>>8)&255)/255.0,(mg.background&255)/255.0,1);
    CGContextFillRect(mg.bitmap,CGRectMake(0,0,width/mg.scale,height/mg.scale));
    if (previous) { draw_bitmap(mg.bitmap,previous,mg.bitmap_scale); CGContextRelease(previous); }
    mg.bitmap_scale=mg.scale;
    CGContextSaveGState(mg.bitmap); mg.damage_saved=false;
}
static void resize_buffer(void);
static void yield_event(void);
static void pump_close(void);
static void display_rate(void);
static int modifiers(NSEvent *e) {
    NSEventModifierFlags f=e.modifierFlags;
    return ((f&NSEventModifierFlagShift)?1:0)|((f&(NSEventModifierFlagControl|NSEventModifierFlagCommand))?2:0);
}
static int key_code(NSEvent *e) {
    NSString *s=e.charactersIgnoringModifiers; if (!s.length) return 0;
    unichar c=[s characterAtIndex:0];
    switch (c) { case 0x7f: return 8; case '\t': case NSBackTabCharacter: return 9;
        case '\r': case NSEnterCharacter: return 13; case 27: return 27;
        case NSLeftArrowFunctionKey: return 37; case NSUpArrowFunctionKey: return 38;
        case NSRightArrowFunctionKey: return 39; case NSDownArrowFunctionKey: return 40;
        case NSHomeFunctionKey: return 36; case NSEndFunctionKey: return 35;
        case NSPageUpFunctionKey: return 33; case NSPageDownFunctionKey: return 34;
        case NSDeleteFunctionKey: return 46; case NSInsertFunctionKey: return 45;
        case NSF10FunctionKey: return 121;
        default: return c>='a' && c<='z' ? c-32 : (c<128 ? c : 0); }
}
@interface MGView : NSView <NSTextInputClient> { NSTrackingArea *pointer_area; }
@end
@implementation MGView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:mg.pointer_shape == 1 ? [NSCursor resizeLeftRightCursor] : mg.pointer_shape == 2 ? [NSCursor IBeamCursor] : [NSCursor arrowCursor]];
}
- (void)drawRect:(NSRect)rect {
    if (!mg.bitmap) return;
    CGContextRef context=NSGraphicsContext.currentContext.CGContext;
    if (!CGRectContainsRect(CGRectMake(0,0,mg.width/mg.bitmap_scale,mg.height/mg.bitmap_scale),rect)) {
        CGContextSetRGBFillColor(context,((mg.background>>16)&255)/255.0,((mg.background>>8)&255)/255.0,(mg.background&255)/255.0,1);
        CGContextFillRect(context,rect);
    }
    // Never stretch the old frame to the new bounds during live resize, and
    // release its snapshot here rather than retaining it in the app's pool.
    draw_region(context,rect);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (pointer_area) [self removeTrackingArea:pointer_area];
    pointer_area=[[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil] autorelease];
    [self addTrackingArea:pointer_area];
}
- (void)mouseEntered:(NSEvent *)e { [self mouseMoved:e]; }
- (void)mouseExited:(NSEvent *)e { [self mouseMoved:e]; }
- (void)mouseMoved:(NSEvent *)e {
    NSPoint p=[self convertPoint:e.locationInWindow fromView:nil]; mg.x=p.x; mg.y=p.y; mg.mods=modifiers(e); mg.event=1;
}
- (void)mouseDragged:(NSEvent *)e { [self mouseMoved:e]; }
- (void)mouseDown:(NSEvent *)e {
    if (mg_mouse_hook && mg_mouse_hook(e)) return;
    [self mouseMoved:e]; [self.window makeFirstResponder:self];
    if (mg.marked) { [[self inputContext] discardMarkedText]; [self unmarkText]; }
    mg.code=(int)((e.clickCount-1)%3)+1; mg.event=2;
}
- (void)mouseUp:(NSEvent *)e { [self mouseMoved:e]; mg.event=3; }
- (void)rightMouseUp:(NSEvent *)e { [self mouseMoved:e]; mg.event=14; }
- (void)scrollWheel:(NSEvent *)e {
    [self mouseMoved:e]; mg.scroll_pixels=e.hasPreciseScrollingDeltas;
    // AppKit already supplies logical points for a trackpad, including
    // acceleration, natural direction and momentum. Coarse deltas are lines.
    mg.delta=mg.scroll_pixels ? e.scrollingDeltaY : e.scrollingDeltaY/3.0f;
    mg.event=4;
}
- (void)keyDown:(NSEvent *)e {
    mg.mods=modifiers(e); mg.code=key_code(e);
    if ((e.modifierFlags&NSEventModifierFlagOption) && (mg.code==8 || mg.code==46 || mg.code==37 || mg.code==39)) mg.mods|=2;
    if (mg.mods&2) { mg.event=5; return; }
    mg.event=0;
    if (mg.owner) [self interpretKeyEvents:@[e]];
    if (!mg.event) mg.event=5;
}
- (void)doCommandBySelector:(SEL)selector { (void)selector; }
- (BOOL)hasMarkedText { return mg.marked.length>0; }
- (NSRange)markedRange { return mg.marked ? NSMakeRange(0,mg.marked.length) : NSMakeRange(NSNotFound,0); }
- (NSRange)selectedRange { return mg.marked ? mg.selected : NSMakeRange(0,0); }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (void)setMarkedText:(id)value selectedRange:(NSRange)selected replacementRange:(NSRange)replacement {
    (void)replacement; NSString *s=[value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
    NSData *bytes=[s dataUsingEncoding:NSUTF8StringEncoding]; if (bytes.length>sizeof(mg.preedit)) return;
    selected.location=MIN(selected.location,s.length); selected.length=MIN(selected.length,s.length-selected.location);
    [mg.marked release]; mg.marked=[s copy]; mg.selected=selected;
    memcpy(mg.preedit,bytes.bytes,bytes.length); mg.length=(int)bytes.length;
    mg.cursor=utf8_prefix(s,selected.location+selected.length); mg.target_start=utf8_prefix(s,selected.location);
    mg.target_end=utf8_prefix(s,MIN(s.length,selected.location+selected.length)); mg.event=10;
}
- (void)unmarkText {
    [mg.marked release]; mg.marked=nil; mg.length=0;
    if (mg.event!=11) mg.event=12;
}
- (void)insertText:(id)value replacementRange:(NSRange)replacement {
    (void)replacement; NSString *s=[value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
    NSData *bytes=[s dataUsingEncoding:NSUTF8StringEncoding]; if (bytes.length>sizeof(mg.result)) return;
    memcpy(mg.result,bytes.bytes,bytes.length); mg.result_length=(int)bytes.length; mg.event=11;
    [mg.marked release]; mg.marked=nil; mg.length=0;
}
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if (!mg.marked || range.location>mg.marked.length) { if (actual) *actual=NSMakeRange(NSNotFound,0); return nil; }
    range.length=MIN(range.length,mg.marked.length-range.location); if (actual) *actual=range;
    return [[[NSAttributedString alloc] initWithString:[mg.marked substringWithRange:range]] autorelease];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point { (void)point; return 0; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if (actual) *actual=range;
    return [self.window convertRectToScreen:[self convertRect:mg.caret toView:nil]];
}
@end
@interface MGDelegate : NSObject <NSWindowDelegate>
@end
@implementation MGDelegate
- (BOOL)windowShouldClose:(NSWindow *)window { (void)window; mg.closed=true; return YES; }
- (void)windowDidResignKey:(NSNotification *)notice { (void)notice; mg.event=7; }
- (void)windowDidMove:(NSNotification *)notice {
    (void)notice; if (mg.owner) [[mg.view inputContext] invalidateCharacterCoordinates];
}
- (void)windowDidResize:(NSNotification *)notice {
    (void)notice; NSSize size=mg.view.bounds.size; if (size.width<1 || size.height<1) return;
    if (mg.owner) [[mg.view inputContext] invalidateCharacterCoordinates];
    mg.resize_pending=true;
    if (!mg.view.inLiveResize || mg.on_dispatch) resize_buffer();
    mg.event=8;
    yield_event();
}
- (void)windowWillStartLiveResize:(NSNotification *)notice {
    (void)notice;
    if (mg.resize_timer) return;
    mg.resize_timer=[[NSTimer timerWithTimeInterval:0.016 target:self selector:@selector(resizeTick:) userInfo:nil repeats:YES] retain];
    [[NSRunLoop mainRunLoop] addTimer:mg.resize_timer forMode:NSEventTrackingRunLoopMode];
}
- (void)resizeTick:(NSTimer *)timer {
    (void)timer; mg.event=9; yield_event();
}
- (void)waitTick:(NSTimer *)timer {
    (void)timer;
    // Give timed waits an explicit run-loop wakeup. AppKit event-fetch
    // expiration alone has substantially more jitter after drawing.
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
        timestamp:0 windowNumber:0 context:nil subtype:0x4d47 data1:mg.wait_serial data2:0x4d795761] atStart:YES];
}
- (void)displayTick:(CADisplayLink *)link {
    if (link!=mg.display_link || !mg.on_dispatch || mg.stopping) return;
    // Retain across the caller-stack yield: the app may disable the link or
    // close the window before this callback resumes.
    [link retain];
    display_rate();
    // Map Core Animation host time to the library's monotonic clock. Sample
    // animations for the upcoming presentation, independently of callback jitter.
    double ahead=link.targetTimestamp-CACurrentMediaTime();
    mg.frame_ns=mg_clock_ns()+(int64_t)((ahead>0 && ahead<10 ? ahead : 0)*1e9);
    mg.event=MG_EVENT_FRAME; yield_event();
    [link release];
    // nextEventMatchingMask can stay inside its run loop indefinitely while
    // display callbacks yield frames. End this fetch after the callback
    // unwinds so its autoreleased framework objects are drained each frame.
    if (!mg.stopping) [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
        timestamp:0 windowNumber:0 context:nil subtype:0x4d47 data1:0 data2:0x4d794672] atStart:YES];
}
- (void)windowDidChangeScreen:(NSNotification *)notice {
    (void)notice; display_rate(); if (mg.owner) [[mg.view inputContext] invalidateCharacterCoordinates];
}
- (void)windowDidEndLiveResize:(NSNotification *)notice {
    (void)notice; [mg.resize_timer invalidate]; [mg.resize_timer release]; mg.resize_timer=nil;
    resize_buffer(); mg.event=8; yield_event();
}
- (void)windowDidChangeBackingProperties:(NSNotification *)notice {
    mg.scale=mg.window.backingScaleFactor;
    clear_text_cache();
    if (mg.owner) [[mg.view inputContext] invalidateCharacterCoordinates];
    [self windowDidResize:notice];
}
@end
static void resize_buffer(void) {
    NSSize size=mg.view.bounds.size;
    if (size.width>=1 && size.height>=1) buffer((int)ceil(size.width*mg.scale),(int)ceil(size.height*mg.scale));
    mg.resize_pending=false;
}
bool mg_dump_requested(void) { const char *s=getenv("MYGOOSE_DUMP"); return s && *s; }
// AppKit sends mouseDragged/mouseUp to the mouse-down view outside its bounds.
// Cancellation remains owned by the shared interaction state.
bool mg_capture(bool enabled) { return mg.headless || mg.window != nil || !enabled; }
void mg_cursor(int32_t shape) {
    if (shape < 0 || shape > 2) shape = 0;
    if (mg.headless || !mg.window || mg.pointer_shape == shape) return;
    mg.pointer_shape = shape; [mg.window invalidateCursorRectsForView:mg.view];
    NSPoint point = [mg.view convertPoint:mg.window.mouseLocationOutsideOfEventStream fromView:nil];
    if (NSPointInRect(point, mg.view.bounds) && mg.window.isKeyWindow)
        [(shape == 1 ? [NSCursor resizeLeftRightCursor] : shape == 2 ? [NSCursor IBeamCursor] : [NSCursor arrowCursor]) set];
}
bool mg_open(mg_string title,int32_t width,int32_t height,bool headless) {
    if (mg.bitmap || width<=0 || height<=0) return false;
    memset(&mg,0,sizeof(mg)); mg.scale=1; mg.x=mg.y=-1; mg.headless=headless||mg_dump_requested();
    const char *renderer=getenv("MYGOOSE_RENDERER"); if (renderer && strcmp(renderer,"coregraphics")) return false;
    mg.pool=[[NSAutoreleasePool alloc] init];
    if (!mg.headless) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        if (!NSApp.mainMenu) {
            NSString *name=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"MyGoose";
            NSMenu *bar=[[[NSMenu alloc] initWithTitle:@""] autorelease];
            NSMenuItem *item=[[[NSMenuItem alloc] initWithTitle:name action:NULL keyEquivalent:@""] autorelease];
            NSMenu *menu=[[[NSMenu alloc] initWithTitle:name] autorelease];
            [menu addItemWithTitle:[@"About " stringByAppendingString:name] action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
            [menu addItem:[NSMenuItem separatorItem]];
            [menu addItemWithTitle:[@"Hide " stringByAppendingString:name] action:@selector(hide:) keyEquivalent:@"h"];
            [menu addItem:[NSMenuItem separatorItem]];
            [menu addItemWithTitle:[@"Quit " stringByAppendingString:name] action:@selector(terminate:) keyEquivalent:@"q"];
            [item setSubmenu:menu]; [bar addItem:item]; [NSApp setMainMenu:bar];
        }
        [NSApp finishLaunching];
        mg.scale=[NSScreen mainScreen].backingScaleFactor; if (mg.scale<=0) mg.scale=1;
    }
    buffer((int)ceil(width*mg.scale),(int)ceil(height*mg.scale)); if (mg.headless) return true;
    mg.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,width,height)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    // Match the RGB8 renderer. Automatic wide-gamut window backing can use
    // half-float surfaces at twice the storage without adding source precision.
    [mg.window setColorSpace:NSColorSpace.sRGBColorSpace];
    [mg.window setReleasedWhenClosed:NO]; [mg.window setTitle:string(title) ?: @"MyGoose"];
    mg.view=[[MGView alloc] initWithFrame:NSMakeRect(0,0,width,height)]; [mg.view setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [mg.window setContentView:mg.view]; [mg.window makeFirstResponder:mg.view]; [mg.window setAcceptsMouseMovedEvents:YES];
    mg.delegate=[[MGDelegate alloc] init]; [mg.window setDelegate:mg.delegate]; [mg.window center];
    if (!mg_defer_show && !getenv("MYGOOSE_HIDDEN")) { [mg.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    return true;
}
void mg_close(void) {
    mg_mouse_hook=NULL; mg_defer_show=false;
    mg_display_sync(0);
    pump_close();
    [mg.resize_timer invalidate]; [mg.resize_timer release];
    if (mg.window) { [mg.window setDelegate:nil]; [mg.window close]; [mg.window release]; }
    [mg.view release]; [mg.delegate release]; [mg.marked release];
    clear_text_cache();
    if (mg.bitmap) CGContextRelease(mg.bitmap);
    NSAutoreleasePool *pool=mg.pool; memset(&mg,0,sizeof(mg)); [pool drain];
}
void *mg_macos_window(void) { return mg.window; }
void mg_macos_defer_show(void) { mg_defer_show=true; }
void mg_macos_mouse_hook(bool (*hook)(void *event)) { mg_mouse_hook=hook; }
void mg_macos_dismiss_focus(void) {
    if (mg.marked) { [[mg.view inputContext] discardMarkedText]; [mg.view unmarkText]; }
    mg.event=7;
}
static int dispatch_events(void) {
    while (!mg.event && !mg.closed) {
        @autoreleasepool {
            if (mg.stopping) return -1;
            NSDate *deadline=mg.wait_timeout>0 ? [NSDate dateWithTimeIntervalSinceReferenceDate:mg.wait_deadline] : [NSDate distantFuture];
            NSEvent *event=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:deadline inMode:NSDefaultRunLoopMode dequeue:YES];
            if (!event) return 9;
            if (event.type==NSEventTypeApplicationDefined && event.subtype==0x4d47 && event.data2==0x4d794672) continue;
            if (event.type==NSEventTypeApplicationDefined && event.subtype==0x4d47 && event.data2==0x4d795761) {
                if (event.data1==mg.wait_serial) return 9;
                continue;
            }
            [NSApp sendEvent:event];
            if (mg.stopping) return -1;
            [NSApp updateWindows];
            if (mg.resize_pending) { resize_buffer(); mg.event=8; }
        }
    }
    return mg.closed ? -1 : mg.event;
}
static void mg_dispatch_main(void) {
    for (;;) {
        mg.dispatching=true; mg.wait_result=dispatch_events(); mg.dispatching=false;
        mg.on_dispatch=false; mg_context_swap(&mg.dispatch_stack.dispatch,&mg.dispatch_stack.caller); mg.on_dispatch=true;
    }
}
static void yield_event(void) {
    // Suspend the native callback, return through mg_wait, and run ordinary
    // Goose event/layout/paint on its original stack before AppKit continues.
    if (!mg.on_dispatch || !mg.dispatching || mg.stopping) return;
    mg.wait_result=mg.event;
    mg.on_dispatch=false; mg_context_swap(&mg.dispatch_stack.dispatch,&mg.dispatch_stack.caller); mg.on_dispatch=true;
}
static void pump_close(void) {
    [mg.wait_timer invalidate]; [mg.wait_timer release]; mg.wait_timer=nil;
    if (!mg.dispatch_stack.mapping) return;
    mg.stopping=true;
    if (mg.dispatching) {
        // A suspended display callback can be inside an indefinite AppKit
        // event fetch. Wake that fetch after unwinding the callback.
        [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
            timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:YES];
        // End AppKit's edge tracking before releasing its suspended stack.
        if (mg.view.inLiveResize) {
            NSEvent *up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:mg.window.mouseLocationOutsideOfEventStream
                modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:mg.window.windowNumber
                context:nil eventNumber:0 clickCount:1 pressure:0];
            [NSApp postEvent:up atStart:YES];
        }
        mg.on_dispatch=true; mg_context_swap(&mg.dispatch_stack.caller,&mg.dispatch_stack.dispatch); mg.on_dispatch=false;
    }
    mg_stack_destroy(&mg.dispatch_stack);
}
int64_t mg_frame_time_ns(void) { return mg.event==MG_EVENT_FRAME && mg.frame_ns>0 ? mg.frame_ns : mg_clock_ns(); }
int32_t mg_display_hz(void) {
    if (mg.headless || !mg.window) return 0;
    if (@available(macOS 12.0,*)) return (int32_t)mg.window.screen.maximumFramesPerSecond;
    return 0;
}
static void display_rate(void) {
    if (@available(macOS 14.0,*)) {
        int maximum=mg_display_hz();
        int rate=maximum>0 ? MIN(mg.display_rate,maximum) : mg.display_rate;
        if (mg.display_link && rate>0 && rate!=mg.display_applied) {
            mg.display_link.preferredFrameRateRange=(CAFrameRateRange){rate,rate,rate};
            mg.display_applied=rate;
        }
    }
}
bool mg_display_sync(int32_t fps) {
    if (fps<=0 || mg.headless || !mg.window) {
        if (@available(macOS 14.0,*)) { [mg.display_link invalidate]; [mg.display_link release]; }
        mg.display_link=nil; mg.display_rate=mg.display_applied=0; return false;
    }
    if (@available(macOS 14.0,*)) {
        if (!mg.display_link) {
            mg.display_link=[[mg.window displayLinkWithTarget:mg.delegate selector:@selector(displayTick:)] retain];
            if (!mg.display_link) return false;
            [mg.display_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        }
        mg.display_rate=MIN(fps,1000); display_rate(); return true;
    }
    return false;
}
int32_t mg_wait(int32_t timeout_ms) {
    if (mg.headless || mg.closed) return -1;
    if (!mg.dispatch_stack.mapping) {
        // AppKit's startup temporaries belong to startup, not the window's
        // lifetime. Native objects kept in mg have their own retained owners.
        [mg.pool drain]; mg.pool=[[NSAutoreleasePool alloc] init];
    }
    if (!mg.dispatch_stack.mapping && !mg_stack_create(&mg.dispatch_stack,mg_dispatch_main)) {
        fputs("MyGoose: cannot initialize the UI event pump\n",stderr); return -1;
    }
    mg.event=0; mg.delta=0; mg.scroll_pixels=false; mg.wait_timeout=timeout_ms;
    mg.wait_deadline=NSDate.timeIntervalSinceReferenceDate+timeout_ms/1000.0;
    mg.wait_serial++;
    if (timeout_ms>0) {
        NSDate *date=[[NSDate alloc] initWithTimeIntervalSinceReferenceDate:mg.wait_deadline];
        mg.wait_timer=[[NSTimer alloc] initWithFireDate:date interval:0 target:mg.delegate selector:@selector(waitTick:) userInfo:nil repeats:NO];
        [date release]; mg.wait_timer.tolerance=0;
        [[NSRunLoop mainRunLoop] addTimer:mg.wait_timer forMode:NSDefaultRunLoopMode];
    }
    mg.on_dispatch=true; mg_context_swap(&mg.dispatch_stack.caller,&mg.dispatch_stack.dispatch); mg.on_dispatch=false;
    [mg.wait_timer invalidate]; [mg.wait_timer release]; mg.wait_timer=nil;
    return mg.wait_result;
}
float mg_event_x(void) { return mg.x; } float mg_event_y(void) { return mg.y; } float mg_event_delta(void) { return mg.delta; }
bool mg_event_scroll_pixels(void) { return mg.scroll_pixels; }
int32_t mg_event_code(void) { return mg.code; } int32_t mg_event_mods(void) { return mg.mods; }
float mg_width(void) { return mg.width/mg.scale; } float mg_height(void) { return mg.height/mg.scale; }
static mg_font *font_for(float size,bool bold) {
    uint32_t bits; memcpy(&bits,&size,sizeof(bits));
    for (int i=0;i<MG_FONT_CACHE;i++) if (mg.fonts[i].font && mg.fonts[i].size==bits && mg.fonts[i].bold==bold) return &mg.fonts[i];
    mg_font *entry=&mg.fonts[mg.next_font++%MG_FONT_CACHE];
    if (entry->font) CFRelease(entry->font);
    CTFontRef font=CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("Helvetica"),size,NULL);
    if (bold) { CTFontRef next=CTFontCreateCopyWithSymbolicTraits(font,0,NULL,kCTFontBoldTrait,kCTFontBoldTrait); if (next) { CFRelease(font); font=next; } }
    // Retaining the font also retains CoreText's per-font shaping data across
    // dynamic labels that miss the line cache. Bound both caches independently.
    // Center the cap/descender band in Goose's size * 1.4 line box. The
    // system font's ascent includes extra space above Latin glyphs; using
    // that em box alone shifts visible text down. Base-font metrics keep
    // adjacent Latin/CJK labels on one baseline.
    double baseline=(size*1.4+CTFontGetCapHeight(font)-CTFontGetDescent(font))*0.5;
    *entry=(mg_font){bits,bold,font,baseline}; return entry;
}
static mg_line *line(mg_string text,float size,bool bold) {
    uint64_t hash=14695981039346656037ULL; for (int64_t i=0;i<text.len;i++) hash=(hash^text.data[i])*1099511628211ULL;
    uint32_t bits; memcpy(&bits,&size,sizeof(bits)); hash=(hash^bits)*1099511628211ULL^bold;
    for (int i=0;i<MG_LINE_CACHE;i++) if (mg.lines[i].line && mg.lines[i].hash==hash) return &mg.lines[i];
    mg_line *entry=&mg.lines[mg.next_line++%MG_LINE_CACHE]; if (entry->line) CFRelease(entry->line);
    mg_font *font=font_for(size,bold);
    CFStringRef value=CFStringCreateWithBytes(NULL,text.data,text.len,kCFStringEncodingUTF8,false);
    if (!value) value=CFStringCreateWithCString(NULL,"",kCFStringEncodingUTF8);
    const void *keys[]={kCTFontAttributeName,kCTForegroundColorFromContextAttributeName}; const void *values[]={font->font,kCFBooleanTrue};
    CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef attributed=CFAttributedStringCreate(NULL,value,attrs); CTLineRef shaped=CTLineCreateWithAttributedString(attributed);
    double width=CTLineGetTypographicBounds(shaped,NULL,NULL,NULL);
    *entry=(mg_line){hash,shaped,width,font->baseline}; CFRelease(attributed); CFRelease(attrs); CFRelease(value); return entry;
}
float mg_measure(mg_string text,float size,bool bold) { return mg.bitmap && text.len>0 && text.len<=65536 ? (float)line(text,size,bold)->width : 0; }
static CGRect pixels_rect(float x,float y,float w,float h) {
    double left=floor(x*mg.scale)/mg.scale,top=floor(y*mg.scale)/mg.scale;
    return CGRectMake(left,top,fmax(0,ceil((x+w)*mg.scale)/mg.scale-left),fmax(0,ceil((y+h)*mg.scale)/mg.scale-top));
}
void mg_clip(float x,float y,float w,float h) {
    CGContextRestoreGState(mg.bitmap); CGContextSaveGState(mg.bitmap);
    CGContextClipToRect(mg.bitmap,pixels_rect(x,y,w,h));
}
static void color(uint32_t c,double alpha) { CGContextSetRGBFillColor(mg.bitmap,((c>>16)&255)/255.0,((c>>8)&255)/255.0,(c&255)/255.0,alpha); }
static void rounded(float x,float y,float w,float h,float radius) {
    CGFloat r=fmax(0,fmin(radius,fmin(w,h)*0.5));
    CGPathRef path=CGPathCreateWithRoundedRect(CGRectMake(x,y,w,h),r,r,NULL); CGContextAddPath(mg.bitmap,path); CGPathRelease(path);
}
void mg_rect(float x,float y,float w,float h,float radius,uint32_t c) {
    if (w<=0 || h<=0) return;
    color(c,1);
    if (radius<=0) { CGContextFillRect(mg.bitmap,CGRectMake(x,y,w,h)); return; }
    if (w==h && radius>=w*.5f) { CGContextFillEllipseInRect(mg.bitmap,CGRectMake(x,y,w,h)); return; }
    rounded(x,y,w,h,radius); CGContextFillPath(mg.bitmap);
}
void mg_shadow(float x,float y,float w,float h,float radius,float blur,float spread,float dx,float dy,uint32_t c,float opacity) {
    if (w<=0 || h<=0 || opacity<=0) return;
    for (int i=24;i>0;i--) { float expand=spread+blur*i/24.0f;
        rounded(x+dx-expand,y+dy-expand,w+2*expand,h+2*expand,radius+expand); color(c,opacity/24); CGContextFillPath(mg.bitmap); }
}
static void begin_damage(uint32_t background) {
    // Save the union clip once per frame. Each node restores that state before
    // applying its own clip, rather than rebuilding a multi-rectangle mask.
    if (mg.damage_saved) CGContextRestoreGState(mg.bitmap);
    CGContextRestoreGState(mg.bitmap); CGContextSaveGState(mg.bitmap);
    CGContextClipToRects(mg.bitmap,mg.damage,mg.damage_count); CGContextSaveGState(mg.bitmap); mg.damage_saved=true;
    mg.background=background; color(background,1); CGContextFillRect(mg.bitmap,mg.dirty);
}
void mg_paint_begin(float x,float y,float w,float h,uint32_t background) {
    mg.dirty=pixels_rect(x,y,w,h); mg.damage[0]=mg.dirty; mg.damage_count=1; begin_damage(background);
}
bool mg_paint_regions(mg_regions regions,uint32_t background) {
    mg_rect_region r=mg_region_bounds(regions);
    mg.dirty=pixels_rect(r.x,r.y,r.w,r.h); mg.damage_count=(int)regions.len;
    for (int i=0;i<mg.damage_count;i++) {
        mg_rect_region b=regions.data[i]; mg.damage[i]=pixels_rect(b.x,b.y,b.w,b.h);
    }
    begin_damage(background); return regions.len>1;
}
void mg_text(mg_string text,float x,float y,float size,bool bold,uint32_t c) {
    if (text.len<=0 || text.len>65536) return; mg_line *entry=line(text,size,bold);
    CGContextSaveGState(mg.bitmap); color(c,1); CGContextTranslateCTM(mg.bitmap,x,y+entry->baseline); CGContextScaleCTM(mg.bitmap,1,-1);
    CGContextSetTextMatrix(mg.bitmap,CGAffineTransformIdentity); CGContextSetTextPosition(mg.bitmap,0,0); CTLineDraw(entry->line,mg.bitmap); CGContextRestoreGState(mg.bitmap);
}
// One AppKit invalidation amortizes image/display-list setup even when the
// CPU painter uses a sparse union. Keep the existing cropped/full snapshot path.
void mg_paint_end(void) { @autoreleasepool { CGContextFlush(mg.bitmap); if (mg.view) { [mg.view setNeedsDisplayInRect:mg.dirty]; [mg.view displayIfNeeded]; } } }
uint64_t mg_pixel_hash(void) { CGContextFlush(mg.bitmap); uint64_t hash=14695981039346656037ULL; for (int64_t i=0;i<(int64_t)mg.width*mg.height;i++) hash=(hash^(mg.pixels[i]&0xffffff))*1099511628211ULL; return hash; }
bool mg_clipboard_set(mg_string text) {
    if (!mg.bitmap || text.len<0 || text.len>65536) return false;
    if (mg.headless) { memcpy(mg.clipboard,text.data,(size_t)text.len); mg.clipboard_length=(int)text.len; mg.clipboard_valid=true; return true; }
    @autoreleasepool { NSString *value=string(text); if (!value) return false;
        NSPasteboard *pasteboard=[NSPasteboard generalPasteboard]; [pasteboard clearContents]; return [pasteboard setString:value forType:NSPasteboardTypeString]; }
}
int64_t mg_clipboard_get(mg_bytes out) {
    if (!mg.bitmap) return -1;
    if (mg.headless) { if (!mg.clipboard_valid || mg.clipboard_length>out.len) return -1; memcpy(out.data,mg.clipboard,(size_t)mg.clipboard_length); return mg.clipboard_length; }
    @autoreleasepool { NSString *s=[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]; if (!s) return -1;
        NSData *value=[s dataUsingEncoding:NSUTF8StringEncoding]; if (value.length>(uint64_t)out.len) return -1;
        memcpy(out.data,value.bytes,value.length); return (int64_t)value.length; }
}
void mg_ime_anchor(uint64_t owner,float x,float y,float w,float h,float size) {
    (void)size; CGRect caret=CGRectMake(x,y,w,h);
    bool changed=mg.owner!=owner;
    bool moved=!CGRectEqualToRect(mg.caret,caret);
    mg.owner=owner; mg.caret=caret;
    if (changed && !owner && mg.marked) { [[mg.view inputContext] discardMarkedText]; [mg.marked release]; mg.marked=nil; mg.length=0; }
    if (mg.view && (changed || (owner && moved))) [[mg.view inputContext] invalidateCharacterCoordinates];
}
int64_t mg_ime_read(mg_bytes out,bool result) { int n=result ? mg.result_length : mg.length; if (n>out.len) n=0; memcpy(out.data,result ? mg.result : mg.preedit,(size_t)n); return n; }
int32_t mg_ime_cursor(void) { return mg.cursor; } int32_t mg_ime_target_start(void) { return mg.target_start; } int32_t mg_ime_target_end(void) { return mg.target_end; }
int32_t mg_renderer(void) { return 3; }
int64_t mg_clock_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (int64_t)t.tv_sec*1000000000+t.tv_nsec; }
int64_t mg_cpu_ns(void) { struct timespec t; return clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t)==0 ? (int64_t)t.tv_sec*1000000000+t.tv_nsec : -1; }
int64_t mg_storage_bytes(void) { return sizeof(mg)+(int64_t)mg.width*mg.height*4; }
int64_t mg_memory_bytes(void) { struct mach_task_basic_info info; mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT; return task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&count)==KERN_SUCCESS ? (int64_t)info.resident_size : -1; }
bool mg_dump(void) {
    const char *path=getenv("MYGOOSE_DUMP"); if (!path || !*path) return false;
    FILE *file=fopen(path,"wb"); if (!file) return false; CGContextFlush(mg.bitmap); fprintf(file,"P6\n%d %d\n255\n",mg.width,mg.height); bool ok=true;
    for (int64_t i=0;i<(int64_t)mg.width*mg.height && ok;i++) { uint32_t p=mg.pixels[i]; uint8_t bytes[3]={(uint8_t)(p>>16),(uint8_t)(p>>8),(uint8_t)p}; ok=fwrite(bytes,1,3,file)==3; }
    return fclose(file)==0 && ok;
}
#include "../vector_target.h"
mg_vector_target mg_get_vector_target(void) {
    return (mg_vector_target){.context=mg.bitmap,.pixels=mg.pixels,.width=mg.width,.height=mg.height,.scale=mg.scale,.renderer=3};
}
