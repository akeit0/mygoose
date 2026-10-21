#include <CoreGraphics/CoreGraphics.h>
#include "image.h"
static void mg_image_release(mg_image_slot *slot) { if (slot->resource) CGImageRelease(slot->resource); }
bool mg_image_draw(int64_t handle, float x, float y, float w, float h, float alpha) {
    mg_image_slot *slot = mg_image_find(handle);
    if (!mg_image_arguments(slot, x, y, w, h, alpha)) return false;
    mg_vector_target host = mg_get_vector_target(); CGContextRef cr = host.context; if (!cr) return false;
    if (!slot->resource) {
        CGDataProviderRef data = CGDataProviderCreateWithData(NULL, slot->pixels, (size_t)slot->width * (size_t)slot->height * 4, NULL);
        if (!data) return false;
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        slot->resource = CGImageCreate(slot->width, slot->height, 8, 32, slot->width * 4, rgb,
            kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, data, NULL, true, kCGRenderingIntentDefault);
        CGColorSpaceRelease(rgb); CGDataProviderRelease(data); if (!slot->resource) return false;
    }
    CGContextSaveGState(cr); CGContextSetAlpha(cr, alpha); CGContextSetInterpolationQuality(cr, kCGInterpolationHigh);
    CGContextTranslateCTM(cr, x, y+h); CGContextScaleCTM(cr, 1, -1);
    CGContextDrawImage(cr, CGRectMake(0, 0, w, h), slot->resource); CGContextRestoreGState(cr); return true;
}
