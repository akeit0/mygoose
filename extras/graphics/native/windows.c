#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define COBJMACROS
#define D2D_USE_C_DEFINITIONS
#include <windows.h>
#include <d2d1.h>
#include "vector.h"
static D2D1_COLOR_F d2d_color(uint32_t c) { return (D2D1_COLOR_F){((c>>16)&255)/255.0f,((c>>8)&255)/255.0f,(c&255)/255.0f,1}; }

static bool mg_v_draw(mg_v_cursor *c,uint32_t count,uint32_t color,float alpha,float stroke,float x,float y) {
    mg_vector_target host=mg_get_vector_target(); if (!host.target) return false;
    ID2D1Factory *factory=host.factory; ID2D1DCRenderTarget *target=host.target; ID2D1SolidColorBrush *solid=host.brush;
    ID2D1PathGeometry *path=NULL; ID2D1GeometrySink *sink=NULL;
    if (FAILED(ID2D1Factory_CreatePathGeometry(factory,&path))) return false;
    if (FAILED(ID2D1PathGeometry_Open(path,&sink))) { ID2D1PathGeometry_Release(path); return false; }
    ID2D1GeometrySink_SetFillMode(sink,D2D1_FILL_MODE_ALTERNATE); bool figure=false;
    for (uint32_t i=0;i<count;i++) { uint8_t verb=0; float p[6]={0}; mg_v_segment(c,&verb,p);
        if (verb==0) {
            if (figure) ID2D1GeometrySink_EndFigure(sink,D2D1_FIGURE_END_OPEN);
            D2D1_POINT_2F point={x+p[0],y+p[1]};
            ID2D1GeometrySink_BeginFigure(sink,point,stroke>0 ? D2D1_FIGURE_BEGIN_HOLLOW : D2D1_FIGURE_BEGIN_FILLED); figure=true;
        }
        if (verb==1) { D2D1_POINT_2F point={x+p[0],y+p[1]}; ID2D1GeometrySink_AddLine(sink,point); }
        if (verb==2) { D2D1_BEZIER_SEGMENT curve={{x+p[0],y+p[1]},{x+p[2],y+p[3]},{x+p[4],y+p[5]}}; ID2D1GeometrySink_AddBezier(sink,&curve); }
        if (verb==3) { ID2D1GeometrySink_EndFigure(sink,D2D1_FIGURE_END_CLOSED); figure=false; }
    }
    if (figure) ID2D1GeometrySink_EndFigure(sink,D2D1_FIGURE_END_OPEN);
    HRESULT hr=ID2D1GeometrySink_Close(sink); ID2D1GeometrySink_Release(sink);
    if (SUCCEEDED(hr)) {
        D2D1_COLOR_F brush=d2d_color(color); brush.a=alpha; ID2D1SolidColorBrush_SetColor(solid,&brush);
        if (stroke>0) {
            D2D1_STROKE_STYLE_PROPERTIES props={D2D1_CAP_STYLE_ROUND,D2D1_CAP_STYLE_ROUND,D2D1_CAP_STYLE_ROUND,D2D1_LINE_JOIN_ROUND,10,D2D1_DASH_STYLE_SOLID,0};
            ID2D1StrokeStyle *style=NULL;
            hr=ID2D1Factory_CreateStrokeStyle(factory,&props,NULL,0,&style);
            if (SUCCEEDED(hr)) { ID2D1DCRenderTarget_DrawGeometry(target,(ID2D1Geometry *)path,(ID2D1Brush *)solid,stroke,style); ID2D1StrokeStyle_Release(style); }
        }
        else ID2D1DCRenderTarget_FillGeometry(target,(ID2D1Geometry *)path,(ID2D1Brush *)solid,NULL);
    }
    ID2D1PathGeometry_Release(path); return SUCCEEDED(hr);
}
