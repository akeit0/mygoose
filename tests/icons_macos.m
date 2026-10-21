#include "../native/macos/platform.m"
#include "../extras/images/native/macos.c"
#include "../apps/monitor/native/icons_macos.m"
#include <assert.h>
double mon_process_value(int32_t row,int32_t field) { return row==0 && field==0 ? getpid() : 0; }
uint64_t mon_process_birth(int32_t row) { return row==0 ? mon_icon_birth(getpid()) : 0; }
double mon_detail_value(int32_t row,int32_t field) { return mon_process_value(row,field); }
uint64_t mon_detail_birth(int32_t row) { return mon_process_birth(row); }
int main(void) {
    assert(mg_open((mg_string){(const uint8_t *)"Icons",5},100,100,true));
    assert([mon_icon_path(@"/Applications/Test.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper") isEqualToString:@"/Applications/Test.app"]);
    assert([mon_icon_path(@"/usr/bin/test") isEqualToString:@"/usr/bin/test"]);
    NSImage *image=[NSImage imageWithSize:NSMakeSize(32,32) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [[NSColor redColor] setFill]; NSRectFill(NSMakeRect(0,0,32,16));
        [[NSColor blueColor] setFill]; NSRectFill(NSMakeRect(0,16,32,16));
        return YES;
    }];
    int64_t uploaded=mon_icon_upload(image); assert(uploaded>0);
    mg_image_slot *slot=mg_image_find(uploaded); assert(slot && slot->width==64);
    assert((slot->pixels[16*64+32]&0xffffff)==0xff0000);
    assert((slot->pixels[48*64+32]&0xffffff)==0x0000ff);
    mg_image_free(uploaded);
    int64_t first=mon_process_icon(0); assert(first>0 && mon_process_icon(0)==first && mon_detail_icon(0)==first);
    assert(mon_icon_for_process(getpid(),mon_icon_birth(getpid())+1)==0);
    assert(mon_process_icon(-1)==0 && mon_detail_icon(-1)==0);
    mon_icons_close(); assert(!mg_image_find(first) && mg_image_bytes==0);
    assert(mon_process_icon(0)>first); mon_icons_close(); mg_close();
    puts("PASS: macOS app/helper icons, upright RGBA, identity/cache reuse, stale identities, cleanup and reopen");
}
