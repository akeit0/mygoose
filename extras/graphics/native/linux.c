#include <cairo/cairo.h>
#include "vector.h"
static bool mg_v_draw(mg_v_cursor *c,uint32_t count,uint32_t rgb,float alpha,float stroke,float x,float y) {
    mg_vector_target host=mg_get_vector_target(); cairo_t *cr=host.context; if (!cr) return false;
    cairo_save(cr); cairo_new_path(cr); cairo_set_fill_rule(cr,CAIRO_FILL_RULE_EVEN_ODD);
    for (uint32_t i=0;i<count;i++) { uint8_t verb=0; float p[6]={0}; if (!mg_v_segment(c,&verb,p)) { cairo_restore(cr); return false; }
        if (verb==0) cairo_move_to(cr,x+p[0],y+p[1]);
        if (verb==1) cairo_line_to(cr,x+p[0],y+p[1]);
        if (verb==2) cairo_curve_to(cr,x+p[0],y+p[1],x+p[2],y+p[3],x+p[4],y+p[5]);
        if (verb==3) cairo_close_path(cr);
    }
    cairo_set_source_rgba(cr,((rgb>>16)&255)/255.0,((rgb>>8)&255)/255.0,(rgb&255)/255.0,alpha);
    if (stroke>0) { cairo_set_line_width(cr,stroke); cairo_set_line_join(cr,CAIRO_LINE_JOIN_ROUND); cairo_set_line_cap(cr,CAIRO_LINE_CAP_ROUND); cairo_stroke(cr); }
    else cairo_fill(cr);
    cairo_restore(cr); return true;
}
