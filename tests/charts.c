#include "../native/vector_target.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

bool mg_chart(mg_string data, float x, float y, float width, float height);
static uint8_t data[1480]; static int length;
static void chart(uint32_t kind, float scale, uint32_t columns) {
    uint32_t header[4] = {kind, 0x32d583, 0xf5b544, columns}; int32_t span = 60;
    memcpy(data, header, 16); uint32_t palette[4] = {0x202124,0x37393e,0xf2f3f5,0x7d8993};
    memcpy(data + 16, palette, 16); memcpy(data + 32, &scale, 4); memcpy(data + 36, &span, 4);
    for (unsigned i = 0; i < columns; ++i) { float values[2] = {i ? 50 : 0, -1}; memcpy(data + 40 + i * 8, values, 8); }
    length = 40 + (int)columns * 8;
}
static bool draw(float width, float height) { return mg_chart((mg_string){data, length}, 0, 0, width, height); }
static uint32_t pixel(int x, int y) { mg_vector_target t = mg_get_vector_target(); return t.pixels[y * t.width + x] & 0xffffff; }
int main(void) {
    assert(mg_open((mg_string){(const uint8_t *)"Monitor chart test",18},300,200,true));
    chart(0, 100, 2); mg_paint_begin(0,0,300,200,0);
    assert(draw(200,80)); mg_paint_end();
    assert(pixel(184,68) == 0x32d583); assert(pixel(184,12) != 0x32d583);
    // A measured zero is dim; an absent sample never invents an active dot.
    assert(pixel(16,68) != 0x32d583);
    float missing = -1; memcpy(data + 48, &missing, 4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end(); assert(pixel(184,68) != 0x32d583);
    // Both rates share a scale and stack, with the secondary series below.
    float primary = 25, secondary = 25; memcpy(data + 48, &primary, 4); memcpy(data + 52, &secondary, 4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    assert(pixel(184,68) == 0xf5b544 && pixel(184,52) == 0x32d583);
    primary = -1; memcpy(data + 48, &primary, 4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end(); assert(pixel(184,68) == 0xf5b544);
    chart(1,.5f,0); mg_paint_begin(0,0,300,200,0); assert(draw(100,100)); mg_paint_end();
    assert(pixel(95,50) == 0x32d583 && pixel(5,50) == 0x37393e);
    chart(1,0,0); mg_paint_begin(0,0,300,200,0); assert(draw(100,100)); mg_paint_end(); assert(pixel(95,50) == 0x37393e);
    chart(1,1,0); mg_paint_begin(0,0,300,200,0); assert(draw(100,100)); mg_paint_end(); assert(pixel(5,50) == 0x32d583);
    // Linux overcommit can exceed its accounting limit; clamp the arc only.
    chart(1,1.25f,0); mg_paint_begin(0,0,300,200,0); assert(draw(100,100)); mg_paint_end();
    chart(1,.25f,0); mg_paint_begin(0,0,300,200,0); assert(draw(100,100)); mg_paint_end();
    assert(pixel(50,5)==0x32d583 && pixel(95,50)==0x32d583 && pixel(50,95)==0x37393e);
    // Partial rings have rounded endpoints and respect the active clip.
    assert(pixel(93,53)==0x32d583 && pixel(95,58)!=0x32d583);
    mg_paint_begin(0,0,300,200,0); mg_clip(90,45,10,10); assert(draw(100,100)); mg_paint_end();
    assert(pixel(95,50)==0x32d583 && pixel(89,50)==0 && pixel(95,55)==0);
    chart(2,.5f,0); mg_paint_begin(0,0,300,200,0); mg_clip(25,0,20,12); assert(draw(200,12)); mg_paint_end();
    assert(pixel(30,5) == 0x32d583 && pixel(24,5) == 0 && pixel(45,5) == 0);
    chart(1,0,0); uint32_t palette[4] = {0xffffff,0xff00ff,0x111111,0x777777}; memcpy(data + 16,palette,16);
    mg_paint_begin(0,0,300,200,0); assert(draw(100,100)); mg_paint_end();
    assert(pixel(5,50) == 0xff00ff && pixel(50,25) == 0xffffff);
    chart(0,100,180);
    for (unsigned i = 0; i < 180; ++i) { float empty[2] = {-1,-1}; memcpy(data + 40 + i * 8, empty, 8); }
    primary = 50; memcpy(data + 40 + 179 * 8, &primary, 4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    // Reducing display density must retain the newest, rightmost sample.
    assert(pixel(184,68) == 0x32d583 && pixel(176,68) != 0x32d583);
    // Histories use one bar per sample, with no width-dependent sampling or
    // interpolation. An old spike moves exactly one slot left on insertion.
    chart(3,100,4);
    for (unsigned i=0;i<4;i++) { float pair[2]={0,-1}; memcpy(data+40+i*8,pair,8); }
    primary=50; memcpy(data+40+3*8,&primary,4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    assert(pixel(166,60)==0x32d583 && pixel(122,60)!=0x32d583);
    primary=0; memcpy(data+40+3*8,&primary,4); primary=50; memcpy(data+40+2*8,&primary,4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    assert(pixel(122,60)==0x32d583 && pixel(166,60)!=0x32d583);
    mg_paint_begin(0,0,300,200,0); assert(draw(100,80)); mg_paint_end();
    assert(pixel(59,60)==0x32d583 && pixel(78,60)!=0x32d583);
    chart(3,100,180);
    for (unsigned i=0;i<180;i++) { float pair[2]={0,-1}; memcpy(data+40+i*8,pair,8); }
    primary=50; memcpy(data+40+73*8,&primary,4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    assert(pixel(83,60)!=pixel(80,60)); // A narrow interior spike must not be skipped.
    chart(3,100,4);
    // Preserve exact (non-quantized) heights and stack both channels.
    primary=25; secondary=25; memcpy(data+40+2*8,&primary,4); memcpy(data+44+2*8,&secondary,4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    assert(pixel(122,68)==0xf5b544 && pixel(122,48)==0x32d583 && pixel(122,32)!=0x32d583);
    primary=-1; secondary=-1; memcpy(data+40+2*8,&primary,4); memcpy(data+44+2*8,&secondary,4);
    mg_paint_begin(0,0,300,200,0); assert(draw(200,80)); mg_paint_end();
    assert(pixel(122,68)!=0xf5b544 && pixel(122,48)!=0x32d583);
    chart(3,100,4); mg_paint_begin(0,0,300,200,0); mg_clip(100,40,20,20); assert(draw(200,80)); mg_paint_end();
    assert(pixel(110,50)==0x32d583 && pixel(99,50)==0 && pixel(120,50)==0);
    uint64_t before = mg_pixel_hash(); chart(0,100,180);
    for (int n = 0; n < length; ++n) assert(!mg_chart((mg_string){data,n},0,0,200,80));
    float nan = NAN; memcpy(data + length - 4, &nan, 4); assert(!draw(200,80));
    chart(3,100,180);
    for (int n=0;n<length;n++) assert(!mg_chart((mg_string){data,n},0,0,200,80));
    memcpy(data+length-4,&nan,4); assert(!draw(200,80));
    chart(3,0,4); assert(!draw(200,80));
    assert(!mg_chart((mg_string){NULL,length},0,0,200,80));
    chart(0,100,2); assert(!mg_chart((mg_string){data,length},NAN,0,200,80));
    assert(!draw(INFINITY,80) && !draw(200,0) && !draw(200,INFINITY) && !draw(20,80));
    uint32_t bad = 181; memcpy(data+12,&bad,4); assert(!draw(200,80));
    chart(0,0,2); assert(!draw(200,80)); chart(0,100,2); memcpy(data,&bad,4); assert(!draw(200,80));
    chart(1,.5f,1); assert(!draw(100,100)); chart(1,.5f,0); assert(!draw(10,10));
    bad = 0x1000000; memcpy(data+16,&bad,4); assert(!draw(100,100));
    assert(mg_pixel_hash() == before);
    mg_close(); puts("PASS: dot/bar histories, discrete sample shifts, stacked/empty/zero samples, ring sectors, overcommit, clipping and validation before painting");
}
