#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define COBJMACROS
#define D2D_USE_C_DEFINITIONS
#include <windows.h>
#include <d2d1.h>
#include "image.h"
static void mg_image_release(mg_image_slot *slot) {
    if (slot->secondary) ID2D1Bitmap_Release((ID2D1Bitmap *)slot->secondary);
}
bool mg_image_draw(int64_t handle, float x, float y, float w, float h, float alpha) {
    mg_image_slot *slot = mg_image_find(handle);
    if (!mg_image_arguments(slot, x, y, w, h, alpha)) return false;
    mg_vector_target host = mg_get_vector_target(); if (!host.target) return false;
    if (alpha == 0) return true;
    ID2D1DCRenderTarget *target = host.target;
    if (slot->secondary && slot->owner != target) { ID2D1Bitmap_Release((ID2D1Bitmap *)slot->secondary); slot->secondary = NULL; }
    if (!slot->secondary) {
        D2D1_SIZE_U size = {(UINT32)slot->width, (UINT32)slot->height};
        D2D1_BITMAP_PROPERTIES props = {{DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED}, 96, 96};
        ID2D1Bitmap *bitmap = NULL;
        if (FAILED(ID2D1DCRenderTarget_CreateBitmap(target, size, slot->pixels, (UINT32)slot->width * 4, &props, &bitmap))) return false;
        slot->secondary = bitmap; slot->owner = target;
    }
    D2D1_RECT_F rect = {x, y, x+w, y+h};
    ID2D1DCRenderTarget_DrawBitmap(target, (ID2D1Bitmap *)slot->secondary, &rect, alpha, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, NULL);
    return true;
}
