#import <Cocoa/Cocoa.h>
#include <libproc.h>
#include "../../../native/backend.h"

double mon_process_value(int32_t row,int32_t field);
uint64_t mon_process_birth(int32_t row);
double mon_detail_value(int32_t row,int32_t field);
uint64_t mon_detail_birth(int32_t row);
int64_t mg_image_create(mg_string rgba,int32_t width,int32_t height);
void mg_image_free(int64_t handle);

/* Visible rows only; one 64px Retina image per application bundle. Both the
   path LRU and PID/creation-time cache are bounded, including negative hits. */
typedef struct { NSString *path; int64_t image; uint64_t used; } mon_icon_entry;
typedef struct { pid_t pid; uint64_t birth,used; int slot; } mon_icon_pid;
static mon_icon_entry mon_icons[64];
static mon_icon_pid mon_icon_pids[512];
static uint64_t mon_icon_clock;

static uint64_t mon_icon_birth(pid_t pid) {
    struct proc_bsdinfo info;
    return proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof info)==sizeof info ?
        info.pbi_start_tvsec*1000000+info.pbi_start_tvusec : 0;
}
static NSString *mon_icon_path(NSString *executable) {
    // Helpers inherit their outer application's icon, not an internal helper.
    NSString *path=@"/";
    for (NSString *part in executable.pathComponents) {
        path=[path stringByAppendingPathComponent:part];
        if ([part.pathExtension caseInsensitiveCompare:@"app"]==NSOrderedSame) return path;
    }
    return executable;
}
static int64_t mon_icon_upload(NSImage *image) {
    if (!image) return 0;
    uint8_t pixels[64*64*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,64,64,8,64*4,space,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space); if (!context) return 0;
    NSRect rect=NSMakeRect(0,0,64,64);
    CGImageRef native=[image CGImageForProposedRect:&rect context:nil hints:nil];
    if (native) { CGContextSetInterpolationQuality(context,kCGInterpolationHigh); CGContextDrawImage(context,CGRectMake(0,0,64,64),native); }
    CGContextRelease(context); if (!native) return 0;
    // The shared image ABI accepts straight RGBA, not CoreGraphics' premultiplied pixels.
    for (int i=0;i<64*64;i++) {
        unsigned alpha=pixels[i*4+3];
        for (int c=0;c<3;c++) pixels[i*4+c]=alpha ? (uint8_t)MIN(255,(pixels[i*4+c]*255+alpha/2)/alpha) : 0;
    }
    return mg_image_create((mg_string){pixels,sizeof pixels},64,64);
}
static int64_t mon_icon_for_process(pid_t pid,uint64_t birth) {
    if (pid<=0 || !birth) return 0;
    @autoreleasepool {
        uint64_t tick=++mon_icon_clock; int oldest_pid=0;
        for (int i=0;i<512;i++) {
            if (mon_icon_pids[i].pid==pid && mon_icon_pids[i].birth==birth) {
                mon_icon_pids[i].used=tick; int slot=mon_icon_pids[i].slot;
                if (slot<0) return 0;
                mon_icons[slot].used=tick; return mon_icons[slot].image;
            }
            if (mon_icon_pids[i].used<mon_icon_pids[oldest_pid].used) oldest_pid=i;
        }
        int slot=-1; char bytes[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pid,bytes,sizeof bytes)>0 && mon_icon_birth(pid)==birth) {
            NSString *path=mon_icon_path([NSString stringWithUTF8String:bytes]); int oldest=0;
            for (int i=0;i<64;i++) {
                if ([mon_icons[i].path isEqualToString:path]) { slot=i; break; }
                if (mon_icons[i].used<mon_icons[oldest].used) oldest=i;
            }
            if (slot<0) {
                slot=oldest;
                for (int i=0;i<512;i++) if (mon_icon_pids[i].pid && mon_icon_pids[i].slot==slot) mon_icon_pids[i]=(mon_icon_pid){0};
                mg_image_free(mon_icons[slot].image); [mon_icons[slot].path release];
                NSImage *image=[[NSWorkspace sharedWorkspace] iconForFile:path];
                mon_icons[slot]=(mon_icon_entry){[path copy],mon_icon_upload(image),tick};
            }
            mon_icons[slot].used=tick;
        }
        mon_icon_pids[oldest_pid]=(mon_icon_pid){pid,birth,tick,slot};
        return slot<0 ? 0 : mon_icons[slot].image;
    }
}
int64_t mon_process_icon(int32_t row) { return mon_icon_for_process((pid_t)mon_process_value(row,0),mon_process_birth(row)); }
int64_t mon_detail_icon(int32_t row) { return mon_icon_for_process((pid_t)mon_detail_value(row,0),mon_detail_birth(row)); }
bool mon_icons_pending(void) { return false; }
void mon_icons_wait(void) {}
void mon_icons_close(void) {
    for (int i=0;i<64;i++) { mg_image_free(mon_icons[i].image); [mon_icons[i].path release]; mon_icons[i]=(mon_icon_entry){0}; }
    memset(mon_icon_pids,0,sizeof mon_icon_pids); mon_icon_clock=0;
}
