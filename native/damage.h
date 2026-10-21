#ifndef MYGOOSE_DAMAGE_H
#define MYGOOSE_DAMAGE_H
#include "backend.h"
#include <assert.h>
#include <math.h>
static mg_rect_region mg_region_bounds(mg_regions regions) {
    assert(regions.len > 0 && regions.len <= MG_MAX_DAMAGE);
    mg_rect_region r=regions.data[0];
    for (int64_t i=1;i<regions.len;i++) {
        mg_rect_region b=regions.data[i];
        float right=fmaxf(r.x+r.w,b.x+b.w),bottom=fmaxf(r.y+r.h,b.y+b.h);
        r.x=fminf(r.x,b.x); r.y=fminf(r.y,b.y); r.w=right-r.x; r.h=bottom-r.y;
    }
    return r;
}
#endif
