#include "../native/vector_target.h"
#include <assert.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
bool mg_vector(mg_string data,float x,float y);
static uint8_t data[256]; static int length;
static void u32(uint32_t n) { memcpy(data+length,&n,4); length+=4; }
static void number(float n) { memcpy(data+length,&n,4); length+=4; }
static void point(uint8_t verb,float x,float y) { data[length++]=verb; number(x); number(y); }
static void box(uint32_t color,float alpha) {
    length=0; u32(color); number(alpha); number(0); u32(5);
    point(0,10,10); point(1,110,10); point(1,110,110); point(1,10,110); data[length++]=3;
}
static uint32_t pixel(int x,int y) { mg_vector_target target=mg_get_vector_target(); return target.pixels[y*target.width+x]&0xffffff; }
int main(void) {
    assert(mg_open((mg_string){(const uint8_t *)"Vector test",11},150,150,true));
    mg_paint_begin(0,0,150,150,0); box(0xff0000,1); assert(mg_vector((mg_string){data,length},0,0)); mg_paint_end();
    assert(pixel(50,50)==0xff0000 && pixel(120,120)==0);
    mg_paint_begin(0,0,150,150,0xff0000); box(0x0000ff,0.5f); assert(mg_vector((mg_string){data,length},0,0)); mg_paint_end();
    uint32_t p=pixel(50,50); assert(abs((int)(p&255)-128)<=1 && abs((int)((p>>16)&255)-128)<=1 && !(p&0xff00));
    mg_paint_begin(0,0,150,150,0); mg_clip(25,25,20,20); box(0xff0000,1); assert(mg_vector((mg_string){data,length},0,0)); mg_paint_end();
    assert(pixel(30,30)==0xff0000 && pixel(24,30)==0 && pixel(45,30)==0);
    uint64_t before=mg_pixel_hash();
    for (int n=1;n<length;n++) assert(!mg_vector((mg_string){data,n},0,0));
    int good=length; data[length++]=255; assert(!mg_vector((mg_string){data,length},0,0)); assert(mg_pixel_hash()==before);
    length=good; float nan=NAN; memcpy(data+4,&nan,4); assert(!mg_vector((mg_string){data,length},0,0));
    assert(!mg_vector((mg_string){data,length},NAN,0)); assert(mg_pixel_hash()==before);
    mg_close(); puts("PASS: native vector pixels, alpha, clipping, truncated/invalid streams and validation before painting");
}
