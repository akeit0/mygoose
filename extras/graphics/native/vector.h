/* Optional vector ABI, included only by backend implementation files.
   Stream per shape: u32 RGB, f32 alpha, f32 stroke (0=fill), u32 segments.
   Segment: u8 verb, then 2 floats for move/line, 6 for cubic, 0 for close.
   Values use host byte order, as Goose bytes_of() does; no unaligned loads.
   Every stream is fully validated before any drawing. */
#ifndef MYGOOSE_VECTOR_H
#define MYGOOSE_VECTOR_H
#include "../../../native/vector_target.h"
#include <math.h>
#include <string.h>
typedef struct { const uint8_t *data; int64_t length,at; } mg_v_cursor;
static bool mg_v_u32(mg_v_cursor *c,uint32_t *out) {
    if (c->length-c->at<4) return false;
    memcpy(out,c->data+c->at,4); c->at+=4; return true;
}
static bool mg_v_float(mg_v_cursor *c,float *out) {
    uint32_t bits; if (!mg_v_u32(c,&bits)) return false; memcpy(out,&bits,4);
    return isfinite(*out) && fabsf(*out)<=1000000;
}
static bool mg_v_segment(mg_v_cursor *c,uint8_t *verb,float points[6]) {
    if (c->at>=c->length) return false;
    *verb=c->data[c->at++]; if (*verb>3) return false;
    int n=*verb==2 ? 6 : *verb==3 ? 0 : 2;
    for (int i=0;i<n;i++) if (!mg_v_float(c,&points[i])) return false;
    return true;
}
static bool mg_v_header(mg_v_cursor *c,uint32_t *color,float *alpha,float *stroke,uint32_t *count) {
    return mg_v_u32(c,color) && mg_v_float(c,alpha) && mg_v_float(c,stroke) && mg_v_u32(c,count) &&
        *alpha>=0 && *alpha<=1 && *stroke>=0 && *stroke<=4096 && *count>0 && *count<=128;
}
static bool mg_v_validate(mg_string data) {
    if (data.len<0 || data.len>65536) return false;
    mg_v_cursor c={data.data,data.len,0};
    while (c.at<c.length) {
        uint32_t color,count; float alpha,stroke;
        if (!mg_v_header(&c,&color,&alpha,&stroke,&count)) return false;
        bool figure=false;
        for (uint32_t i=0;i<count;i++) { uint8_t verb; float points[6];
            if (!mg_v_segment(&c,&verb,points) || (verb!=0 && !figure)) return false;
            if (verb==0) figure=true; else if (verb==3) figure=false;
        }
    } return true;
}
static bool mg_v_draw(mg_v_cursor *c,uint32_t count,uint32_t color,float alpha,float stroke,float x,float y);
bool mg_vector(mg_string data,float x,float y) {
    if (!isfinite(x) || !isfinite(y) || fabsf(x)>1000000 || fabsf(y)>1000000 || !mg_v_validate(data)) return false;
    mg_v_cursor c={data.data,data.len,0};
    while (c.at<c.length) {
        uint32_t color,count; float alpha,stroke; if (!mg_v_header(&c,&color,&alpha,&stroke,&count)) return false;
        if (!mg_v_draw(&c,count,color,alpha,stroke,x,y)) return false;
    } return true;
}
#endif
