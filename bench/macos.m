/* Isolate CoreText cache misses and chart-style square bars, without AppKit
   presentation. Run each binary in a fresh process; compare identical builds.
   clang -Os -flto bench/macos.m -o build/macos-render-bench \
     -framework Cocoa -framework CoreText -framework CoreGraphics -framework QuartzCore
*/
#include "../native/macos/platform.m"
#include <assert.h>

static void text_bench(void) {
    char text[96]; double checksum=0;
    for (int i=0;i<1000;i++) {
        int length=snprintf(text,sizeof(text),"Warmup %d",i);
        checksum+=mg_measure((mg_string){(uint8_t *)text,length},13,i%2);
    }
    int64_t start=mg_clock_ns(),cpu=mg_cpu_ns();
    const int count=30000;
    for (int i=0;i<count;i++) {
        int length=snprintf(text,sizeof(text),"Frame %d: %.1f ms",i,i/17.0);
        checksum+=mg_measure((mg_string){(uint8_t *)text,length},i%3==0 ? 26 : 13,i%2);
    }
    printf("text misses=%d ns/line=%lld cpu_ns/line=%lld rss_bytes=%lld checksum=%.3f\n",count,
        (long long)((mg_clock_ns()-start)/count),(long long)((mg_cpu_ns()-cpu)/count),
        (long long)mg_memory_bytes(),checksum);
}
static void bars(int frame) {
    mg_paint_begin(0,0,1000,760,0x171717);
    for (int i=0;i<720;i++) {
        float height=(i*17+frame)%100+1;
        mg_rect(12+(i%120)*8,12+(i/120)*120+100-height,5,height,0,0x4488cc);
    }
    mg_paint_end();
}
int main(void) {
    assert(mg_open((mg_string){(uint8_t *)"bench",5},1000,760,true));
    mg.scale=2; buffer(2000,1520);
    text_bench();
    for (int i=0;i<30;i++) bars(i);
    int64_t start=mg_clock_ns(),cpu=mg_cpu_ns(); const int count=1000;
    for (int i=0;i<count;i++) bars(i);
    printf("rect frames=%d bars/frame=720 ns/frame=%lld cpu_ns/frame=%lld rss_bytes=%lld pixels=%llu\n",count,
        (long long)((mg_clock_ns()-start)/count),(long long)((mg_cpu_ns()-cpu)/count),
        (long long)mg_memory_bytes(),(unsigned long long)mg_pixel_hash());
    mg_close();
}
