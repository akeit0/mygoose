/* Requires an actual macOS WindowServer. Does not touch NSPasteboard. */
#include "../native/macos/platform.m"
#include <assert.h>
#include <fenv.h>
static int released_probes;
@interface MGReleaseProbe : NSObject
@end
@implementation MGReleaseProbe
- (void)dealloc { released_probes++; [super dealloc]; }
@end
@interface MGResizeFixture : MGView {
@public BOOL resizing;
}
@end
@implementation MGResizeFixture
- (BOOL)inLiveResize { return resizing; }
@end
@interface MGWaitDriver : NSObject
- (void)wake:(NSTimer *)timer;
@end
@implementation MGWaitDriver
- (void)wake:(NSTimer *)timer {
    (void)timer; assert(NSThread.isMainThread && mg.on_dispatch);
    mg.event=7; yield_event();
}
@end
static void wait_tests(void) {
    // Drain opening/geometry events before checking timeout behavior.
    while (mg_wait(1)!=9) {}
    MGWaitDriver *driver=[[MGWaitDriver alloc] init];
    NSTimer *interrupt=[NSTimer scheduledTimerWithTimeInterval:0.005 target:driver selector:@selector(wake:) userInfo:nil repeats:NO];
    assert(mg_wait(1000)==7 && !mg.wait_timer);
    [interrupt invalidate];
    // A canceled long wait must not wake the next indefinite idle wait.
    interrupt=[NSTimer scheduledTimerWithTimeInterval:0.005 target:driver selector:@selector(wake:) userInfo:nil repeats:NO];
    assert(mg_wait(0)==7 && !mg.wait_timer);
    [interrupt invalidate];
    // Ignore a wake marker left over from an earlier wait, even if queued
    // ahead of normal events. It must not shorten a new deadline.
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
        timestamp:0 windowNumber:0 context:nil subtype:0x4d47 data1:mg.wait_serial data2:0x4d795761] atStart:YES];
    int64_t start=mg_clock_ns();
    assert(mg_wait(5)==9 && mg_clock_ns()-start>=4000000 && !mg.wait_timer);
    for (int i=0;i<20;i++) { assert(mg_wait(1)==9 && !mg.wait_timer); }
    [driver release];
    puts("PASS: timed/indefinite AppKit waits, input interruption, timer cleanup and stale deadline markers");
}
@interface MGDisplayDriver : NSObject {
@public BOOL resumed;
}
- (void)frame:(NSTimer *)timer;
@end
@implementation MGDisplayDriver
- (void)frame:(NSTimer *)timer {
    (void)timer; assert(NSThread.isMainThread && mg.on_dispatch); resumed=NO;
    [[[MGReleaseProbe alloc] init] autorelease];
    [mg.delegate displayTick:mg.display_link]; resumed=YES;
}
@end
static void display_tests(void) {
    if (@available(macOS 14.0,*)) {
        assert(mg_display_sync(120)); CADisplayLink *link=mg.display_link;
        assert(link && mg.display_applied==MIN(120,mg_display_hz()));
        assert(mg_display_sync(120) && mg.display_link==link); // Reuse the link on input.
        assert(mg_display_sync(30) && mg.display_link==link && mg.display_applied==MIN(30,mg_display_hz()));
        // Pause hardware callbacks so the fixture is independent of screen
        // visibility and refresh timing, then inject through the actual pump.
        link.paused=YES;
        MGDisplayDriver *driver=[[MGDisplayDriver alloc] init];
        int probes=released_probes;
        [NSTimer scheduledTimerWithTimeInterval:0.001 target:driver selector:@selector(frame:) userInfo:nil repeats:NO];
        int64_t start=mg_clock_ns();
        assert(mg_wait(0)==MG_EVENT_FRAME && !mg.wait_timer && !driver->resumed);
        assert(released_probes==probes); // The callback's native pool is still active.
        int64_t animation=mg_frame_time_ns(); assert(animation>=start && animation==mg_frame_time_ns());
        assert(NSThread.isMainThread && !mg.on_dispatch);
        mg_paint_begin(0,0,mg_width(),mg_height(),0x123456); mg_paint_end();
        assert(!mg_display_sync(0) && !mg.display_link);
        assert(mg_wait(2)==9 && driver->resumed); // Resume a callback after disabling its link.
        assert(released_probes==probes+1);
        [driver release];
        assert(mg_display_sync(60)); mg.display_link.paused=YES;
        driver=[[MGDisplayDriver alloc] init]; probes=released_probes;
        for (int i=0;i<12;i++) {
            driver->resumed=NO;
            [NSTimer scheduledTimerWithTimeInterval:0.001 target:driver selector:@selector(frame:) userInfo:nil repeats:NO];
            assert(mg_wait(1000)==MG_EVENT_FRAME && !driver->resumed);
            // Frame boundaries are internal: they must drain previous native
            // temporaries without returning a timeout/input event to Goose.
            assert(released_probes==probes+i);
        }
        mg_display_sync(0); assert(mg_wait(2)==9 && driver->resumed && released_probes==probes+12);
        [driver release];
        assert(mg_display_sync(120)); mg.display_link.paused=YES; driver=[[MGDisplayDriver alloc] init];
        [NSTimer scheduledTimerWithTimeInterval:0.001 target:driver selector:@selector(frame:) userInfo:nil repeats:NO];
        assert(mg_wait(0)==MG_EVENT_FRAME && !driver->resumed);
        mg_close(); // Unwind an in-flight display callback before freeing its target/stack.
        assert(driver->resumed && !mg.display_link && !mg.dispatch_stack.mapping);
        [driver release];
        assert(mg_open((mg_string){(const uint8_t *)"AppKit test",11},200,150,false));
    } else { assert(!mg_display_sync(120)); }
    puts("PASS: display rate limits/reuse, main-thread frame dispatch, per-frame native autorelease, disable/close inside a display callback and reopen");
}
static uint32_t pixel(int x,int y) { return mg.pixels[y*mg.width+x]&0xffffff; }
static void presentation_tests(void) {
    const CGRect clips[]={{{0,0},{200,150}},{{9.25,12.75},{7.5,11.25}},{{-5,-7},{20,30}},
        {{197.25,145.5},{50,60}},{{201,151},{10,10}},{{0.25,0.75},{0.5,0.5}}};
    for (int scale=1;scale<=2;scale++) {
        assert(mg_open((mg_string){(uint8_t *)"Present",7},200,150,true));
        mg.scale=scale; buffer(200*scale,150*scale);
        mg_paint_begin(0,0,200,150,0x123456);
        for (int i=0;i<100;i++) mg_rect((i*17)%190,(i*13)%140,9.5,7.25,0,(i*6197)^0x44aaff);
        mg_text((mg_string){(uint8_t *)"Top / 日本語",15},10,20,14,false,0xffffff); mg_paint_end();
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        // A larger destination also covers newly exposed resize regions.
        int width=250*scale,height=200*scale; size_t bytes=(size_t)width*height*4;
        CGContextRef targets[2];
        for (int n=0;n<2;n++) {
            targets[n]=CGBitmapContextCreate(NULL,width,height,8,width*4,space,kCGBitmapByteOrder32Little|kCGImageAlphaNoneSkipFirst);
            CGContextTranslateCTM(targets[n],0,height); CGContextScaleCTM(targets[n],scale,-scale);
        }
        CGColorSpaceRelease(space);
        for (unsigned c=0;c<sizeof(clips)/sizeof(clips[0]);c++) {
            for (int n=0;n<2;n++) {
                CGContextSetRGBFillColor(targets[n],0.1,0.2,0.3,1);
                CGContextFillRect(targets[n],CGRectMake(0,0,250,200));
                CGContextSaveGState(targets[n]); CGContextClipToRect(targets[n],clips[c]);
                if (n) draw_region(targets[n],clips[c]); else draw_bitmap(targets[n],mg.bitmap,mg.bitmap_scale);
                CGContextRestoreGState(targets[n]); CGContextFlush(targets[n]);
            }
            assert(!memcmp(CGBitmapContextGetData(targets[0]),CGBitmapContextGetData(targets[1]),bytes));
        }
        for (int n=0;n<2;n++) CGContextRelease(targets[n]);
        // The provider must own only this region, and remain immutable after
        // framebuffer writes, reallocation and close while AppKit retains it.
        CGImageRef image=copy_region(CGRectMake(10,12,7,11));
        assert(image && CGImageGetWidth(image)==7 && CGImageGetHeight(image)==11);
        CFDataRef before=CGDataProviderCopyData(CGImageGetDataProvider(image));
        assert(CFDataGetLength(before)==7*11*4);
        mg_paint_begin(0,0,200,150,0); mg_paint_end(); buffer(300*scale,230*scale); mg_close();
        CFDataRef after=CGDataProviderCopyData(CGImageGetDataProvider(image));
        assert(CFEqual(before,after)); CFRelease(before); CFRelease(after); CGImageRelease(image);
    }
    puts("PASS: cropped presentation equals full-image pixels at 1x/2x, fractional clips/edges/resize, and independent immutable region lifetime");
}
static void damage_tests(void) {
    for (int scale=1;scale<=2;scale++) {
        assert(mg_open((mg_string){(uint8_t *)"Damage",6},200,150,true));
        mg.scale=scale; buffer(200*scale,150*scale);
        mg_paint_begin(0,0,200,150,0x123456); mg_paint_end();
        mg_rect_region regions[]={{10.25f,12.75f,7.5f,11.25f},{160.25f,120.25f,10.5f,9.25f},{14.25f,17.25f,8.5f,12.5f}};
        assert(mg_paint_regions((mg_regions){regions,3},0xabcdef));
        // A node spanning both updates must not fill the untouched gap.
        mg_clip(0,0,200,150); mg_rect(0,0,200,150,0,0xff3300); mg_paint_end();
        for (int y=0;y<mg.height;y++) for (int x=0;x<mg.width;x++) {
            bool damaged=false;
            for (int i=0;i<3;i++) {
                mg_rect_region r=regions[i]; CGRect p=pixels_rect(r.x,r.y,r.w,r.h);
                damaged |= CGRectContainsPoint(p,CGPointMake((x+0.5)/scale,(y+0.5)/scale));
            }
            assert(pixel(x,y)==(damaged?0xff3300:0x123456));
        }
        // Ordinary begin resets the previous union clip.
        mg_paint_begin(0,0,200,150,0x224466); mg_paint_end(); assert(pixel(100*scale,75*scale)==0x224466);
        mg_close();
    }
    puts("PASS: native damage union preserves gaps at 1x/2x, fractional pixel coverage and single-rectangle reset");
}
@interface MGAnchorFixture : MGView { @public int requests; }
@end
@implementation MGAnchorFixture
- (NSTextInputContext *)inputContext { requests++; return [super inputContext]; }
@end
static void anchor_tests(void) {
    assert(mg_open((mg_string){(uint8_t *)"Anchor",6},200,150,true));
    MGAnchorFixture *view=[[MGAnchorFixture alloc] initWithFrame:NSMakeRect(0,0,200,150)]; mg.view=view;
    for (int i=0;i<100;i++) mg_ime_anchor(0,0,0,1,1,14);
    assert(view->requests==0);
    mg_ime_anchor(42,10,20,1,14,14); assert(view->requests==1);
    for (int i=0;i<100;i++) mg_ime_anchor(42,10,20,1,14,14);
    assert(view->requests==1);
    mg_ime_anchor(42,11,20,1,14,14); assert(view->requests==2);
    mg_ime_anchor(43,11,20,1,14,14); assert(view->requests==3);
    MGDelegate *delegate=[[[MGDelegate alloc] init] autorelease];
    NSNotification *notice=[NSNotification notificationWithName:NSWindowDidMoveNotification object:nil];
    [delegate windowDidMove:notice]; [delegate windowDidChangeScreen:notice]; [delegate windowDidResize:notice]; assert(view->requests==6);
    mg_ime_anchor(0,0,0,1,1,14); assert(view->requests==7);
    mg_ime_anchor(0,0,0,1,1,14); [delegate windowDidMove:notice]; assert(view->requests==7);
    mg_close();
    puts("PASS: IME position notifications on owner/caret/window/screen changes, no repeated inactive or stationary invalidations");
}
static void rectangle_tests(void) {
    for (int scale=1;scale<=2;scale++) {
        assert(mg_open((mg_string){(uint8_t *)"Rectangles",10},200,150,true));
        mg.scale=scale; buffer(200*scale,150*scale);
        for (int clipped=0;clipped<=1;clipped++) {
            uint64_t reference=0;
            for (int fast=0;fast<=1;fast++) {
                mg_paint_begin(0.25,0.75,199,149,0x123456);
                if (clipped) mg_clip(15.25,20.75,140.5,98.25);
                for (int i=0;i<100;i++) {
                    float x=(i*17)%190-5+(i%4)*0.25f,y=(i*13)%140-5+(i%3)*0.25f;
                    float w=(i%19)+0.25f,h=(i%23)+0.75f,r=i%2 ? 0 : -2;
                    if (fast) mg_rect(x,y,w,h,r,0x77cc44);
                    else { rounded(x,y,w,h,r); color(0x77cc44,1); CGContextFillPath(mg.bitmap); }
                }
                mg_paint_end();
                if (!fast) reference=mg_pixel_hash(); else assert(reference==mg_pixel_hash());
            }
        }
        mg_close();
    }
    puts("PASS: rectangle fast path matches path pixels at 1x/2x, fractional edges, clipping and negative radii");
}
static void circle_tests(void) {
    for (int scale=1;scale<=2;scale++) {
        assert(mg_open((mg_string){(uint8_t *)"Circles",7},200,150,true));
        mg.scale=scale; buffer(200*scale,150*scale);
        size_t bytes=(size_t)mg.width*mg.height*4; uint32_t *reference=malloc(bytes); assert(reference);
        for (int clipped=0;clipped<=1;clipped++) {
            for (int fast=0;fast<=1;fast++) {
                mg_paint_begin(0,0,200,150,0x123456);
                if (clipped) mg_clip(15.25,20.75,140.5,98.25);
                for (int i=0;i<100;i++) {
                    float x=(i*17)%190-5+(i%4)*.25f,y=(i*13)%140-5+(i%3)*.25f;
                    float size=(i%29)+.4f,r=size*.5f+(i%2)*2;
                    if (fast) mg_rect(x,y,size,size,r,0x77cc44);
                    else { rounded(x,y,size,size,r); color(0x77cc44,1); CGContextFillPath(mg.bitmap); }
                }
                mg_paint_end();
                if (!fast) memcpy(reference,mg.pixels,bytes);
                else {
                    unsigned maximum=0;
                    for (size_t i=0;i<bytes/4;i++) for (int shift=0;shift<24;shift+=8) {
                        unsigned delta=(unsigned)abs((int)((reference[i]>>shift)&255)-(int)((mg.pixels[i]>>shift)&255));
                        if (delta>maximum) maximum=delta;
                    }
                    printf("Circle path maximum channel difference, %dx clipped=%d: %u\n",scale,clipped,maximum);
                    assert(maximum==0);
                }
            }
        }
        free(reference); mg_close();
    }
    puts("PASS: circle fast path matches rounded-circle coverage at 1x/2x, fractional bounds, oversized radii and clipping");
}
static void font_cache_tests(void) {
    assert(mg_open((mg_string){(uint8_t *)"Fonts",5},200,150,true));
    const char *texts[]={"Latin Ag09", "日本語とABC", "Emoji 🌈 👨‍👩‍👧", "العربية हिन्दी"};
    for (int scale=1;scale<=2;scale++) {
        mg.scale=scale; buffer(200*scale,150*scale);
        for (int bold=0;bold<=1;bold++) for (int i=0;i<4;i++) {
            mg_string text={(uint8_t *)texts[i],(int64_t)strlen(texts[i])};
            mg_paint_begin(0,0,200,150,0); mg_text(text,10,20,14.25,bold,0xffffff); mg_paint_end();
            uint64_t reference=mg_pixel_hash(); float width=mg_measure(text,14.25,bold);
            CTFontRef shared=font_for(14.25,bold)->font;
            // More dynamic labels than the line cache can hold still share
            // the same retained font and its CoreText shaping tables.
            for (int n=0;n<MG_LINE_CACHE+10;n++) {
                char bytes[32]; int length=snprintf(bytes,sizeof(bytes),"Label %d",n);
                mg_measure((mg_string){(uint8_t *)bytes,length},14.25,bold);
            }
            assert(font_for(14.25,bold)->font==shared);
            assert(mg_measure(text,14.25,bold)==width);
            mg_paint_begin(0,0,200,150,0); mg_text(text,10,20,14.25,bold,0xffffff); mg_paint_end();
            assert(mg_pixel_hash()==reference);
            // Eviction must not invalidate CTLines retaining older fonts.
            for (int n=0;n<MG_FONT_CACHE*3;n++) font_for(10+n*0.125f,n%2);
            assert(mg_measure(text,14.25,bold)==width);
            mg_paint_begin(0,0,200,150,0); mg_text(text,10,20,14.25,bold,0xffffff); mg_paint_end();
            assert(mg_pixel_hash()==reference);
        }
    }
    clear_text_cache();
    assert(mg.next_line==0 && mg.next_font==0);
    for (int i=0;i<MG_FONT_CACHE;i++) assert(!mg.fonts[i].font);
    for (int i=0;i<MG_LINE_CACHE;i++) assert(!mg.lines[i].line);
    mg_close();
    assert(mg_open((mg_string){(uint8_t *)"Fonts",5},200,150,true));
    assert(mg.next_font==0 && mg.next_line==0); font_for(14,false); mg_close();
    for (int i=0;i<MG_FONT_CACHE;i++) assert(!mg.fonts[i].font);
    puts("PASS: font reuse across line churn, fractional sizes/weights, multilingual shaping, eviction, reset/close/reopen");
}
static void resize_tests(void) {
    mg_string title={(const uint8_t *)"Resize",6};
    for (int scale=1;scale<=2;scale++) {
        assert(mg_open(title,200,150,true)); mg.scale=scale; buffer(200*scale,150*scale);
        mg_paint_begin(0,0,200,150,0x123456);
        mg_rect(10,10,20,20,0,0xff0000); mg_rect(10,120,20,20,0,0x00ff00); mg_paint_end();
        buffer(300*scale,230*scale);
        assert(pixel(15*scale,15*scale)==0xff0000 && pixel(15*scale,125*scale)==0x00ff00);
        assert(pixel(250*scale,200*scale)==0x123456);
        buffer(100*scale,80*scale); buffer(200*scale,150*scale);
        assert(pixel(15*scale,15*scale)==0xff0000 && pixel(15*scale,125*scale)==0x123456);
        // A backing-scale change must rebuild the transform even when the
        // physical dimensions are identical, retaining logical coordinates.
        mg.scale=3-scale; buffer(200*scale,150*scale);
        assert(mg.bitmap_scale==mg.scale && pixel(15*(3-scale),15*(3-scale))==0xff0000);
        mg_close();
    }
    puts("PASS: resize preserves top-left content, fills exposed regions, handles shrink/grow and backing-scale changes");
}
static void live_resize_tests(void) {
    NSSize original=mg.view.bounds.size;
    MGResizeFixture *view=[[MGResizeFixture alloc] initWithFrame:mg.view.frame];
    view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [mg.window setContentView:view]; [mg.view release]; mg.view=view;
    mg_paint_begin(0,0,original.width,original.height,0x123456);
    mg_rect(10,10,20,20,0,0xff0000); mg_paint_end();
    CGContextRef painted=mg.bitmap; int width=mg.width,height=mg.height;
    view->resizing=YES;
    for (int i=1;i<=10;i++) {
        [mg.window setContentSize:NSMakeSize(original.width+i*10,original.height+i*10)];
        [mg.delegate windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:mg.window]];
        assert(mg.resize_pending && mg.bitmap==painted && mg.width==width && mg.height==height);
    }
    view->resizing=NO; resize_buffer();
    assert(!mg.resize_pending && mg_width()==original.width+100 && mg_height()==original.height+100);
    assert(pixel(15*mg.scale,15*mg.scale)==0xff0000);
    assert(pixel((original.width+50)*mg.scale,(original.height+50)*mg.scale)==0x123456);
    puts("PASS: nested AppKit resize retains the painted bitmap until the application can repaint");
}
@interface MGResizeDriver : NSObject {
@public int step,tracking_ticks; BOOL finished;
}
- (void)run:(NSTimer *)timer;
@end
@implementation MGResizeDriver
- (void)run:(NSTimer *)timer {
    (void)timer; assert(NSThread.isMainThread && mg.on_dispatch);
    MGResizeFixture *view=(MGResizeFixture *)mg.view;
    NSSize original=view.bounds.size;
    NSNotification *notice=[NSNotification notificationWithName:NSWindowDidResizeNotification object:mg.window];
    view->resizing=YES; [mg.delegate windowWillStartLiveResize:notice];
    fesetround(FE_DOWNWARD);
    for (step=1;step<=40 && !mg.stopping;step++) {
        [mg.window setContentSize:NSMakeSize(original.width+step*2,original.height+step)];
        if (mg.stopping) break;
        [mg.delegate windowDidResize:notice];
        if (mg.stopping) break;
        assert(mg.on_dispatch && NSThread.isMainThread && fegetround()==FE_DOWNWARD);
        // The outer loop must have laid out/painted the new right/bottom
        // corner before this still-active native resize callback continues.
        assert(mg_width()==view.bounds.size.width && mg_height()==view.bounds.size.height);
        assert(pixel(mg.width-2,mg.height-2)==0xabcdef);
        if (step==3) {
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:1];
            while (!tracking_ticks && deadline.timeIntervalSinceNow>0)
                [[NSRunLoop mainRunLoop] runMode:NSEventTrackingRunLoopMode beforeDate:deadline];
        }
    }
    fesetround(FE_TONEAREST);
    view->resizing=NO; [mg.delegate windowDidEndLiveResize:notice];
    finished=YES;
    // Wake the nextEventMatchingMask call whose run loop fired this fixture.
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
        timestamp:0 windowNumber:mg.window.windowNumber context:nil subtype:0 data1:0 data2:0] atStart:YES];
}
@end
static void dispatch_resize_tests(bool close_during_resize) {
    assert(!mg.dispatch_stack.mapping);
    MGResizeDriver *driver=[[MGResizeDriver alloc] init];
    [NSTimer scheduledTimerWithTimeInterval:0.001 target:driver selector:@selector(run:) userInfo:nil repeats:NO];
    int resizes=0,ticks=0;
    while (!driver->finished) {
        assert(fegetround()==FE_TONEAREST);
        int kind=mg_wait(50);
        assert(NSThread.isMainThread && !mg.on_dispatch && fegetround()==FE_TONEAREST);
        if (kind==8) {
            assert(mg_width()==mg.view.bounds.size.width && mg_height()==mg.view.bounds.size.height);
            mg_paint_begin(0,0,mg_width(),mg_height(),0x123456);
            mg_rect(mg_width()-10,mg_height()-10,10,10,0,0xabcdef); mg_paint_end(); resizes++;
            if (close_during_resize && driver->step>=2) { mg_close(); break; }
        }
        if (kind==9 && mg.dispatching) { ticks++; driver->tracking_ticks++; }
        assert(kind>=0);
    }
    assert(driver->finished && resizes>=2);
    if (close_during_resize) assert(!mg.dispatch_stack.mapping && !mg.window);
    else { assert(resizes>=40 && ticks>0 && !mg.resize_timer && !mg.dispatching); }
    [driver release];
    puts(close_during_resize ? "PASS: closing during suspended native resize unwinds callbacks and releases dispatch storage" :
        "PASS: continuous nested resize, caller-stack painting, idle tracking timer and floating-point/main-thread state");
}
@interface MGScrollFixture : NSEvent {
@public BOOL precise; CGFloat amount;
}
@end
@implementation MGScrollFixture
- (BOOL)hasPreciseScrollingDeltas { return precise; }
- (CGFloat)scrollingDeltaY { return amount; }
- (NSPoint)locationInWindow { return NSMakePoint(30,30); }
- (NSEventModifierFlags)modifierFlags { return 0; }
@end
static void scroll_tests(void) {
    MGScrollFixture *event=[[[MGScrollFixture alloc] init] autorelease];
    float scale=mg.scale;
    for (int retina=1;retina<=2;retina++) {
        mg.scale=retina; event->precise=YES; event->amount=-12.5;
        [mg.view scrollWheel:event]; assert(mg_event_scroll_pixels() && mg_event_delta()==-12.5);
        event->amount=0.125;
        [mg.view scrollWheel:event]; assert(mg_event_scroll_pixels() && mg_event_delta()==0.125);
        event->precise=NO; event->amount=-3;
        [mg.view scrollWheel:event]; assert(!mg_event_scroll_pixels() && mg_event_delta()==-1);
    }
    mg.scale=scale;
    puts("PASS: precise/fractional point scrolling, coarse wheel lines and Retina-independent distance");
}
static void text_alignment_tests(void) {
    mg_string title={(const uint8_t *)"Text metrics",12}, text={(const uint8_t *)"Hg",2};
    for (int scale=1;scale<=2;scale++) {
        assert(mg_open(title,200,150,true));
        mg.scale=scale; mg.width=0; buffer(200*scale,150*scale);
        for (int bold=0;bold<=1;bold++) for (int size=14;size<=28;size+=14) {
            mg_paint_begin(0,0,200,150,0); mg_text(text,10,20,size,bold,0xffffff); mg_paint_end();
            int top=mg.height,bottom=-1;
            for (int y=0;y<mg.height;y++) for (int x=0;x<mg.width;x++)
                if (mg.pixels[y*mg.width+x]&0xffffff) { top=MIN(top,y); bottom=MAX(bottom,y); }
            assert(bottom>=top);
            double center=(top+bottom+1)/(2.0*scale), expected=20+size*1.4/2;
            assert(fabs(center-expected)<=size*0.08+1.0/scale);
        }
        mg_close();
    }
    puts("PASS: text ink centered in logical line boxes at 1x/2x, regular/bold and multiple sizes");
}
static void startup_pool_tests(void) {
    assert(mg_open((mg_string){(uint8_t *)"Startup",7},200,150,false));
    int probes=released_probes;
    [[[MGReleaseProbe alloc] init] autorelease];
    assert(!mg.dispatch_stack.mapping && released_probes==probes);
    assert(mg_wait(1)>=0 && released_probes==probes+1); mg_close();
    puts("PASS: startup autoreleased objects are released before native event dispatch");
}
int main(void) {
    presentation_tests(); damage_tests();
    anchor_tests();
    rectangle_tests();
    circle_tests();
    font_cache_tests();
    text_alignment_tests();
    resize_tests();
    setenv("MYGOOSE_HIDDEN","1",1);
    startup_pool_tests();
    mg_string title={(const uint8_t *)"AppKit test",11}; assert(mg_open(title,200,150,false));
    assert(mg.window && mg.view && mg.scale>=1);
    assert([mg.window.colorSpace isEqual:NSColorSpace.sRGBColorSpace]);
    assert(mg.view.isOpaque);
    font_for(14,false); mg_measure(title,14,false);
    [mg.delegate windowDidChangeBackingProperties:[NSNotification notificationWithName:NSWindowDidChangeBackingPropertiesNotification object:mg.window]];
    assert(mg.next_font==0 && mg.next_line==0);
    [mg.view updateTrackingAreas]; [mg.view updateTrackingAreas];
    int pointer_areas=0; for (NSTrackingArea *area in mg.view.trackingAreas) if (area.owner==mg.view) pointer_areas++;
    assert(pointer_areas==1);
    NSEvent *exit=[NSEvent enterExitEventWithType:NSEventTypeMouseExited location:NSMakePoint(-2,mg.view.bounds.size.height+2)
        modifierFlags:0 timestamp:0 windowNumber:mg.window.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
    [mg.view mouseExited:exit]; assert(mg.event==1 && mg.x<0 && mg.y<0);
    scroll_tests();
    live_resize_tests();
    dispatch_resize_tests(false);
    wait_tests();
    display_tests();
    assert(NSApp.mainMenu.numberOfItems > 0);
    NSMenu *menu=[NSApp.mainMenu itemAtIndex:0].submenu;
    assert([menu itemWithTag:0] && [menu itemAtIndex:menu.numberOfItems-1].action == @selector(terminate:));
    assert(mg_capture(true)); assert(mg_capture(false));
    mg_cursor(1); assert(mg.pointer_shape == 1);
    mg_cursor(2); assert(mg.pointer_shape == 2);
    mg_cursor(0); assert(mg.pointer_shape == 0);
    mg_ime_anchor(42,20,30,1,20,14);
    [mg.view setMarkedText:@"日本" selectedRange:NSMakeRange(2,0) replacementRange:NSMakeRange(NSNotFound,0)];
    assert(mg.event==10 && mg.length==6 && mg.cursor==6);
    assert([mg.view hasMarkedText]);
    [mg.view insertText:@"日本" replacementRange:NSMakeRange(NSNotFound,0)];
    assert(mg.event==11 && mg.result_length==6 && ![mg.view hasMarkedText]);
    assert(memcmp(mg.result,"\xe6\x97\xa5\xe6\x9c\xac",6)==0);
    NSRange actual; NSRect caret=[mg.view firstRectForCharacterRange:NSMakeRange(0,0) actualRange:&actual];
    assert(caret.size.width==1 && caret.size.height==20);
    mg_paint_begin(0,0,200,150,0x123456); mg_paint_end(); assert(mg_pixel_hash()!=0);
    [mg.window setContentSize:NSMakeSize(320,240)];
    [mg.delegate windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:mg.window]];
    assert(mg_width()==320 && mg_height()==240);
    [mg.window performClose:nil]; assert(mg_wait(1)==-1); mg_close();
    assert(mg_open(title,200,150,false));
    MGResizeFixture *view=[[MGResizeFixture alloc] initWithFrame:mg.view.frame];
    view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [mg.window setContentView:view]; [mg.view release]; mg.view=view;
    dispatch_resize_tests(true);
    assert(mg_open(title,32,32,true)); mg_close();
    puts("PASS: AppKit lifecycle, CoreGraphics, UTF-8 marked/committed text and candidate rectangle");
}
