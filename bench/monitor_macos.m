/* Monitor work isolated from AppKit presentation. Build with the same -Os
   -flto flags as the app and link extras/charts/native/macos.c (charts.c
   before the native chart renderer). No process names or paths are logged. */
#include "../native/macos/platform.m"
#include "../apps/monitor/native/macos.c"
#include <assert.h>

bool mg_chart(mg_string data,float x,float y,float width,float height);
static void chart_bench(int kind) {
    uint8_t bytes[1480]={0}; uint32_t header[]={kind,0x3794ff,0xf5b544,kind ? 0 : 60};
    uint32_t palette[]={0x202124,0x37393e,0xf2f3f5,0x7d8993};
    float scale=kind ? .62f : 100; int span=60;
    memcpy(bytes,header,16); memcpy(bytes+16,palette,16); memcpy(bytes+32,&scale,4); memcpy(bytes+36,&span,4);
    for (int i=0;i<60;i++) { float pair[]={i*17%100,-1}; memcpy(bytes+40+i*8,pair,8); }
    mg_string payload={bytes,kind ? 40 : 520};
    int64_t start=0,cpu=0; const int count=1000;
    for (int i=-30;i<count;i++) {
        if (!i) { start=mg_clock_ns(); cpu=mg_cpu_ns(); }
        mg_paint_begin(0,0,360,180,0x202124);
        assert(mg_chart(payload,10,10,kind ? 160 : 330,160)); mg_paint_end();
    }
    printf("chart kind=%d ns/frame=%lld cpu_ns/frame=%lld rss_bytes=%lld hash=%llu\n",kind,
        (long long)((mg_clock_ns()-start)/count),(long long)((mg_cpu_ns()-cpu)/count),
        (long long)mg_memory_bytes(),(unsigned long long)mg_pixel_hash());
}
static void query_bench(int rows,bool cold) {
    mon_count=rows; ++mon_epoch;
    for (int i=0;i<rows;i++) mon_rows[i]=(mon_process){.pid=(uint32_t)(i+10),.birth=1,.known=true,
        .memory=(uint64_t)(i*1777%8191),.cpu=i*13%100};
    for (int i=0;i<rows;i++) snprintf(mon_rows[i].name,sizeof mon_rows[i].name,"Synthetic %d",i);
    int64_t start=mg_clock_ns(),cpu=mg_cpu_ns(); uint64_t checksum=0; const int count=1000;
    for (int i=0;i<count;i++) {
        if (cold) ++mon_epoch;
        assert(mon_query(mon_string(""),1,false)==rows); checksum+=(uint64_t)mon_process_value(0,0);
        assert(mon_query(mon_string(""),2,false)==rows); checksum+=(uint64_t)mon_process_value(0,0);
    }
    printf("query rows=%d cold=%d ns/pair=%lld cpu_ns/pair=%lld checksum=%llu\n",rows,cold,
        (long long)((mg_clock_ns()-start)/count),(long long)((mg_cpu_ns()-cpu)/count),(unsigned long long)checksum);
}
int main(void) {
    assert(mg_open((mg_string){(uint8_t *)"Monitor benchmark",17},1240,820,true));
    mg.scale=2; buffer(2480,1640);
    chart_bench(0); chart_bench(1);
    for (int i=-5;i<40;i++) { mon_last=0; assert(mon_sample()); }
    int64_t start=mg_clock_ns(),cpu=mg_cpu_ns();
    for (int i=0;i<40;i++) { mon_last=0; assert(mon_sample()); }
    printf("sampler rows=%d ns/sample=%lld cpu_ns/sample=%lld rss_bytes=%lld\n",mon_count,
        (long long)((mg_clock_ns()-start)/40),(long long)((mg_cpu_ns()-cpu)/40),(long long)mg_memory_bytes());
    query_bench(512,false); query_bench(4096,false);
    query_bench(512,true); query_bench(4096,true);
    mon_close(); mg_close();
}
