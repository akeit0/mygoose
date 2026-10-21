#include <CoreGraphics/CoreGraphics.h>
#include "vector.h"
static bool mg_v_draw(mg_v_cursor *c,uint32_t count,uint32_t rgb,float alpha,float stroke,float x,float y) {
    mg_vector_target host=mg_get_vector_target(); CGContextRef bitmap=host.context; if (!bitmap) return false;
    CGContextSaveGState(bitmap); CGContextBeginPath(bitmap);
    for (uint32_t i=0;i<count;i++) { uint8_t verb=0; float p[6]={0}; if (!mg_v_segment(c,&verb,p)) { CGContextRestoreGState(bitmap); return false; }
        if (verb==0) CGContextMoveToPoint(bitmap,x+p[0],y+p[1]);
        if (verb==1) CGContextAddLineToPoint(bitmap,x+p[0],y+p[1]);
        if (verb==2) CGContextAddCurveToPoint(bitmap,x+p[0],y+p[1],x+p[2],y+p[3],x+p[4],y+p[5]);
        if (verb==3) CGContextClosePath(bitmap);
    }
    if (stroke>0) {
        CGContextSetRGBStrokeColor(bitmap,((rgb>>16)&255)/255.0,((rgb>>8)&255)/255.0,(rgb&255)/255.0,alpha);
        CGContextSetLineWidth(bitmap,stroke); CGContextSetLineJoin(bitmap,kCGLineJoinRound); CGContextSetLineCap(bitmap,kCGLineCapRound); CGContextStrokePath(bitmap);
    } else { CGContextSetRGBFillColor(bitmap,((rgb>>16)&255)/255.0,((rgb>>8)&255)/255.0,(rgb&255)/255.0,alpha); CGContextEOFillPath(bitmap); }
    CGContextRestoreGState(bitmap); return true;
}
