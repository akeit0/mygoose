/* Optional CoreGraphics chart renderer. Uses the existing drawing target;
   importing charts adds no new dependency or persistent backing storage. */
#include "../../../native/vector_target.h"
#include <CoreGraphics/CoreGraphics.h>
static void mg_ch_native_arc(float cx,float cy,float radius,float thickness,float amount,uint32_t color) {
    CGContextRef context=mg_get_vector_target().context;
    if (!context) return;
    const double pi=3.14159265358979323846;
    CGContextSaveGState(context);
    CGContextSetRGBStrokeColor(context,((color>>16)&255)/255.,((color>>8)&255)/255.,(color&255)/255.,1);
    CGContextSetLineWidth(context,thickness); CGContextSetLineCap(context,kCGLineCapRound);
    if (amount>=1) CGContextStrokeEllipseInRect(context,CGRectMake(cx-radius,cy-radius,2*radius,2*radius));
    else {
        CGContextBeginPath(context);
        CGContextAddArc(context,cx,cy,radius,-pi/2,-pi/2+amount*2*pi,false);
        CGContextStrokePath(context);
    }
    CGContextRestoreGState(context);
}
#define MG_CH_ARC mg_ch_native_arc
#include "charts.c"
