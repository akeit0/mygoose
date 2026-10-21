#include "../native/vector_target.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
int64_t mg_image_create(mg_string rgba, int32_t width, int32_t height);
void mg_image_free(int64_t handle);
bool mg_image_draw(int64_t handle, float x, float y, float w, float h, float opacity);
static int channel(uint32_t pixel, int shift) { return (pixel >> shift) & 255; }
static uint32_t pixel(int x, int y) { mg_pixel_hash(); mg_vector_target t = mg_get_vector_target(); return t.pixels[y*t.width+x] & 0xffffff; }
int main(void) {
    assert(mg_open((mg_string){(const uint8_t *)"images",6}, 20, 20, true));
    const uint8_t rgba[] = {255,64,0,128}; mg_string data = {rgba, sizeof rgba};
    assert(!mg_image_create(data, 0, 1)); assert(!mg_image_create(data, 4097, 1));
    assert(!mg_image_create((mg_string){rgba,3}, 1, 1));
    int64_t handle = mg_image_create(data, 1, 1); assert(handle > 0);
    mg_paint_begin(0,0,20,20,0); mg_clip(4,4,4,4);
    assert(mg_image_draw(handle,2,2,10,10,1)); mg_paint_end();
    assert(pixel(3,5) == 0 && pixel(8,5) == 0);
    uint32_t p = pixel(5,5); assert(abs(channel(p,16)-128) <= 2 && abs(channel(p,8)-32) <= 2 && channel(p,0) == 0);
    mg_paint_begin(0,0,20,20,0); mg_clip(0,0,20,20);
    assert(mg_image_draw(handle,2,2,10,10,.5f)); mg_paint_end();
    p = pixel(5,5); assert(abs(channel(p,16)-64) <= 2 && abs(channel(p,8)-16) <= 2);
    assert(!mg_image_draw(handle,0,0,-1,1,1)); assert(!mg_image_draw(handle,NAN,0,1,1,1));
    assert(!mg_image_draw(handle,0,0,1,1,2));
    mg_image_free(handle); mg_image_free(handle); assert(!mg_image_draw(handle,0,0,1,1,1));
    int64_t newer = mg_image_create(data,1,1); assert(newer > handle); mg_image_free(newer);
    int64_t ids[128]; for (int i=0;i<128;++i) { ids[i]=mg_image_create(data,1,1); assert(ids[i]>0); }
    assert(!mg_image_create(data,1,1)); for (int i=0;i<128;++i) mg_image_free(ids[i]);
    mg_close(); puts("PASS: image upload bounds, alpha/opacity pixels, scaling, clips, stale handles and bounded capacity"); fflush(stdout); return 0;
}
