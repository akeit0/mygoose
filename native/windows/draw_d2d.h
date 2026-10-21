/* Windows drawing uses Direct2D and DirectWrite for every app and test. */
#define COBJMACROS
#define D2D_USE_C_DEFINITIONS
#include <d2d1.h>
#include <dwrite.h>

typedef struct { IDWriteTextFormat *format; float size; bool bold; } mg_dwrite_format;
typedef struct { IDWriteTextLayout *layout; uint64_t hash; int length; float width; } mg_dwrite_layout;
static struct {
    ID2D1Factory *factory;
    IDWriteFactory *write;
    ID2D1DCRenderTarget *target;
    ID2D1SolidColorBrush *brush;
    HRGN damage_region, damage_part;
    int damage_saved_dc;
    mg_dwrite_format formats[32];
    mg_dwrite_layout layouts[256];
    int count, next, width, height;
    float scale;
    bool node_clip;
} d2d;
static void d2d_close(void) {
    for (int i = 0; i < 256; i++) if (d2d.layouts[i].layout) IDWriteTextLayout_Release(d2d.layouts[i].layout);
    for (int i = 0; i < 32; i++) if (d2d.formats[i].format) IDWriteTextFormat_Release(d2d.formats[i].format);
    if (d2d.damage_region) DeleteObject(d2d.damage_region);
    if (d2d.damage_part) DeleteObject(d2d.damage_part);
    if (d2d.brush) ID2D1SolidColorBrush_Release(d2d.brush);
    if (d2d.target) ID2D1DCRenderTarget_Release(d2d.target);
    if (d2d.write) IDWriteFactory_Release(d2d.write);
    if (d2d.factory) ID2D1Factory_Release(d2d.factory);
    memset(&d2d, 0, sizeof(d2d));
}
static bool d2d_open(void) {
    static const GUID d2d_guid = {0x06152247,0x6f50,0x465a,{0x92,0x45,0x11,0x8b,0xfd,0x3b,0x60,0x07}};
    static const GUID write_guid = {0xb859ee5a,0xd838,0x4b5b,{0xa2,0xe8,0x1a,0xdc,0x7d,0x93,0xdb,0x48}};
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &d2d_guid, NULL, (void **)&d2d.factory))) goto fail;
    if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &write_guid, (IUnknown **)&d2d.write))) goto fail;
    // A software DC target keeps headless and native windows on the same
    // rasterizer, without loading a GPU driver or reserving GPU textures.
    D2D1_RENDER_TARGET_PROPERTIES props = {D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        {DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE}, 96.0f, 96.0f,
        D2D1_RENDER_TARGET_USAGE_NONE, D2D1_FEATURE_LEVEL_DEFAULT};
    if (FAILED(ID2D1Factory_CreateDCRenderTarget(d2d.factory, &props, &d2d.target))) goto fail;
    D2D1_COLOR_F white = {1,1,1,1};
    if (FAILED(ID2D1DCRenderTarget_CreateSolidColorBrush(d2d.target, &white, NULL, &d2d.brush))) goto fail;
    ID2D1DCRenderTarget_SetAntialiasMode(d2d.target, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    // Grayscale is stable in exported images and on RGB/BGR/rotated screens.
    ID2D1DCRenderTarget_SetTextAntialiasMode(d2d.target, D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    return true;
fail:
    d2d_close(); return false;
}
static IDWriteTextFormat *d2d_format(float size, bool bold) {
    for (int i = 0; i < d2d.count; i++)
        if (d2d.formats[i].size == size && d2d.formats[i].bold == bold) return d2d.formats[i].format;
    int slot = d2d.count < 32 ? d2d.count++ : d2d.next++ % 32;
    mg_dwrite_format *f = &d2d.formats[slot];
    if (f->format) IDWriteTextFormat_Release(f->format);
    f->format = NULL; f->size = size; f->bold = bold;
    HRESULT hr = IDWriteFactory_CreateTextFormat(d2d.write, L"Segoe UI", NULL,
        bold ? DWRITE_FONT_WEIGHT_SEMI_BOLD : DWRITE_FONT_WEIGHT_NORMAL,
        DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size, L"", &f->format);
    if (FAILED(hr)) { fputs("MyGoose: DirectWrite format failed\n", stderr); exit(1); }
    IDWriteTextFormat_SetWordWrapping(f->format, DWRITE_WORD_WRAPPING_NO_WRAP);
    return f->format;
}
static mg_dwrite_layout *d2d_layout(mg_string text, float size, bool bold) {
    uint64_t h = 14695981039346656037ULL;
    for (int64_t i = 0; i < text.len; i++) h = (h ^ text.data[i]) * 1099511628211ULL;
    uint32_t size_bits; memcpy(&size_bits, &size, sizeof(size_bits));
    h = ((h ^ size_bits) * 1099511628211ULL) ^ bold;
    mg_dwrite_layout *entry = &d2d.layouts[h % 256];
    if (entry->layout && entry->hash == h && entry->length == text.len) return entry;
    if (entry->layout) IDWriteTextLayout_Release(entry->layout);
    entry->layout = NULL; entry->hash = h; entry->length = (int)text.len;
    int len = mg_wide(text, mg_wide_buffer, 65536);
    HRESULT hr = IDWriteFactory_CreateTextLayout(d2d.write, mg_wide_buffer, len,
        d2d_format(size, bold), 1048576.0f, 1048576.0f, &entry->layout);
    if (FAILED(hr)) { fputs("MyGoose: DirectWrite layout failed\n", stderr); exit(1); }
    DWRITE_TEXT_METRICS metrics;
    IDWriteTextLayout_GetMetrics(entry->layout, &metrics); entry->width = metrics.widthIncludingTrailingWhitespace;
    return entry;
}
static D2D1_COLOR_F d2d_color(uint32_t c) {
    D2D1_COLOR_F color = {((c>>16)&255)/255.0f, ((c>>8)&255)/255.0f, (c&255)/255.0f, 1.0f}; return color;
}
static void d2d_begin(float x, float y, float w, float h, uint32_t background) {
    if (d2d.width != mg.width || d2d.height != mg.height || d2d.scale != mg.scale) {
        RECT r = {0,0,mg.width,mg.height};
        GdiFlush();
        if (FAILED(ID2D1DCRenderTarget_BindDC(d2d.target, mg.dc, &r))) { fputs("MyGoose: Direct2D BindDC failed\n",stderr); exit(1); }
        ID2D1DCRenderTarget_SetDpi(d2d.target, 96.0f * mg.scale, 96.0f * mg.scale);
        d2d.width = mg.width; d2d.height = mg.height; d2d.scale = mg.scale;
    }
    ID2D1DCRenderTarget_BeginDraw(d2d.target);
    // Align damage clips to physical pixels. Fractional clips can multiply
    // antialiasing coverage when a partial frame redraws a boundary pixel.
    D2D1_RECT_F clip = {px(x)/mg.scale, px(y)/mg.scale, edge(x+w)/mg.scale, edge(y+h)/mg.scale};
    ID2D1DCRenderTarget_PushAxisAlignedClip(d2d.target, &clip, D2D1_ANTIALIAS_MODE_ALIASED);
    D2D1_COLOR_F color = d2d_color(background); ID2D1DCRenderTarget_Clear(d2d.target, &color);
    d2d.node_clip = false;
}
static bool d2d_begin_regions(mg_regions regions, mg_rect_region bounds, uint32_t background) {
    // Dense damage keeps the simple path. Sum (rather than union) area makes
    // overlap conservatively favor fallback and needs no region-sized bitmap.
    double area = 0.0;
    for (int64_t i = 0; i < regions.len; i++) {
        mg_rect_region r = regions.data[i];
        area += (double)(edge(r.x+r.w)-px(r.x))*(edge(r.y+r.h)-px(r.y));
    }
    double bounding_area = (double)(edge(bounds.x+bounds.w)-px(bounds.x))*(edge(bounds.y+bounds.h)-px(bounds.y));
    bool sparse = area*2 < bounding_area;
    if (sparse) {
        if (!d2d.damage_region) d2d.damage_region = CreateRectRgn(0,0,0,0);
        if (!d2d.damage_part) d2d.damage_part = CreateRectRgn(0,0,0,0);
        sparse = d2d.damage_region && d2d.damage_part && SetRectRgn(d2d.damage_region,0,0,0,0);
        for (int64_t i = 0; sparse && i < regions.len; i++) {
            mg_rect_region r = regions.data[i];
            sparse = SetRectRgn(d2d.damage_part,px(r.x),px(r.y),edge(r.x+r.w),edge(r.y+r.h)) &&
                CombineRgn(d2d.damage_region,d2d.damage_region,d2d.damage_part,RGN_OR) != ERROR;
        }
    }
    d2d_begin(bounds.x,bounds.y,bounds.w,bounds.h,background);
    // EndDraw transfers the Direct2D output to its bound DC. Clip that copy
    // to the integer-pixel union, preserving retained pixels in the gaps. The
    // shared painter can then skip their nodes, including optional painters.
    if (sparse) {
        int saved = SaveDC(mg.dc);
        if (saved && ExtSelectClipRgn(mg.dc,d2d.damage_region,RGN_AND) != ERROR) {
            d2d.damage_saved_dc = saved; return true;
        }
        if (saved) RestoreDC(mg.dc,saved);
    }
    return false;
}
static void d2d_clip(float x, float y, float w, float h) {
    if (d2d.node_clip) ID2D1DCRenderTarget_PopAxisAlignedClip(d2d.target);
    D2D1_RECT_F clip = {px(x)/mg.scale, px(y)/mg.scale, edge(x+w)/mg.scale, edge(y+h)/mg.scale};
    ID2D1DCRenderTarget_PushAxisAlignedClip(d2d.target, &clip, D2D1_ANTIALIAS_MODE_ALIASED);
    d2d.node_clip = true;
}
static void d2d_rect(float x, float y, float w, float h, float radius, uint32_t c) {
    D2D1_COLOR_F color = d2d_color(c); ID2D1SolidColorBrush_SetColor(d2d.brush, &color);
    D2D1_RECT_F r = {x,y,x+w,y+h};
    if (radius > 0.0f) {
        D2D1_ROUNDED_RECT rounded = {r, radius, radius};
        ID2D1DCRenderTarget_FillRoundedRectangle(d2d.target, &rounded, (ID2D1Brush *)d2d.brush);
    } else ID2D1DCRenderTarget_FillRectangle(d2d.target, &r, (ID2D1Brush *)d2d.brush);
}
static void d2d_text(mg_string text, float x, float y, float size, bool bold, uint32_t c) {
    mg_dwrite_layout *layout = d2d_layout(text, size, bold);
    D2D1_COLOR_F color = d2d_color(c); ID2D1SolidColorBrush_SetColor(d2d.brush, &color);
    D2D1_POINT_2F origin = {x,y};
    ID2D1DCRenderTarget_DrawTextLayout(d2d.target, origin, layout->layout,
        (ID2D1Brush *)d2d.brush, D2D1_DRAW_TEXT_OPTIONS_NONE);
}
static void d2d_shadow(float x, float y, float w, float h, float radius,
                           float blur, float spread, float dx, float dy, uint32_t c, float opacity) {
    if (blur <= 0) {
        D2D1_COLOR_F color = d2d_color(c); color.a = opacity;
        ID2D1SolidColorBrush_SetColor(d2d.brush, &color);
        float r = fmaxf(0,radius+spread);
        D2D1_ROUNDED_RECT rect = {{x+dx-spread,y+dy-spread,x+dx+w+spread,y+dy+h+spread},r,r};
        ID2D1DCRenderTarget_FillRoundedRectangle(d2d.target, &rect, (ID2D1Brush *)d2d.brush);
        return;
    }
    // Layered coverage approximates a cubic blur without a temporary bitmap,
    // effect graph or GPU resources. Work is bounded to 24 rounded rectangles.
    const int steps = 24;
    float total = 0.0f;
    for (int i = 0; i < steps; i++) { float t = (i+0.5f)/steps; total += 6*t*(1-t); }
    float cumulative = 0.0f;
    for (int i = 0; i < steps; i++) {
        float t = (i+0.5f)/steps, weight = 6*t*(1-t)/total;
        float d = spread + blur*(1-2*t);
        float denominator = 1-opacity*cumulative;
        D2D1_COLOR_F color = d2d_color(c);
        color.a = denominator > 0 ? fminf(1,fmaxf(0,opacity*weight/denominator)) : 0;
        cumulative += weight;
        if (w+2*d <= 0 || h+2*d <= 0) continue;
        ID2D1SolidColorBrush_SetColor(d2d.brush, &color);
        float r = fmaxf(0, radius+d);
        D2D1_ROUNDED_RECT rect = {{x+dx-d,y+dy-d,x+dx+w+d,y+dy+h+d},r,r};
        ID2D1DCRenderTarget_FillRoundedRectangle(d2d.target, &rect, (ID2D1Brush *)d2d.brush);
    }
}
static void d2d_end(void) {
    if (d2d.node_clip) ID2D1DCRenderTarget_PopAxisAlignedClip(d2d.target);
    ID2D1DCRenderTarget_PopAxisAlignedClip(d2d.target); d2d.node_clip = false;
    HRESULT hr = ID2D1DCRenderTarget_EndDraw(d2d.target, NULL, NULL);
    if (d2d.damage_saved_dc) { RestoreDC(mg.dc,d2d.damage_saved_dc); d2d.damage_saved_dc = 0; }
    if (FAILED(hr)) { fprintf(stderr,"MyGoose: Direct2D EndDraw failed (0x%08lx)\n",(unsigned long)hr); exit(1); }
}
