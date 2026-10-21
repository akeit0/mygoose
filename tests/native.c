/* ABI tests, independent of an OS window server and the user's clipboard. */
#include "../native/backend.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void) {
    mg_string title={(const uint8_t *)"Native ABI test",15};
    assert(mg_open(title,200,150,true)); assert(!mg_open(title,200,150,true));
    assert(mg_frame_time_ns()>0);
    assert(!mg_display_sync(120) && mg_display_hz()==0 && !mg_display_sync(0));
    assert(mg_width()==200 && mg_height()==150);
    mg_string text={(const uint8_t *)"hello",5}; assert(mg_measure(text,14,false)>0);
    mg_paint_begin(0,0,200,150,0x123456); mg_paint_end(); uint64_t first=mg_pixel_hash();
    mg_paint_begin(10,10,20,20,0xabcdef); mg_paint_end(); assert(mg_pixel_hash()!=first);
    mg_paint_begin(0,0,200,150,0x123456); mg_paint_end(); assert(mg_pixel_hash()==first);
    mg_rect_region regions[]={{10,10,20,20},{150,100,20,20}};
    bool sparse=mg_paint_regions((mg_regions){regions,2},0xabcdef);
    mg_clip(0,0,200,150); mg_rect(0,0,200,150,0,0xff3300); mg_paint_end();
    uint64_t region_hash=mg_pixel_hash();
    mg_paint_begin(0,0,200,150,0x123456); mg_paint_end();
    if (sparse) {
        mg_paint_begin(10,10,20,20,0xff3300); mg_paint_end();
        mg_paint_begin(150,100,20,20,0xff3300); mg_paint_end();
    } else { mg_paint_begin(10,10,160,110,0xff3300); mg_paint_end(); }
    assert(region_hash==mg_pixel_hash());
    uint8_t value[65536]; memset(value,'x',sizeof(value));
    assert(mg_clipboard_set((mg_string){value,sizeof(value)}));
    assert(mg_clipboard_get((mg_bytes){value,sizeof(value)-1})==-1);
    assert(mg_clipboard_get((mg_bytes){value,sizeof(value)})==65536);
    assert(!mg_clipboard_set((mg_string){value,65537}));
    assert(mg_wait(1)==-1); assert(mg_clock_ns()>0 && mg_storage_bytes()>=200*150*4);
    int64_t cpu=mg_cpu_ns(); assert(cpu>=0);
    volatile uint64_t work=1;
    for (int i=0;i<1000000;i++) work=work*1664525+1013904223;
    assert(mg_cpu_ns()>=cpu); // Some platforms account CPU in coarse quanta.
    mg_close(); assert(mg_open(title,32,32,true)); mg_close();
    puts("PASS: native ABI, headless rendering, exact-capacity clipboard and lifecycle");
}
