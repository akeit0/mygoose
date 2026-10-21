#include <cairo/cairo.h>
#include "image.h"
static void mg_image_release(mg_image_slot *slot) { if (slot->resource) cairo_surface_destroy(slot->resource); }
bool mg_image_draw(int64_t handle, float x, float y, float w, float h, float alpha) {
    mg_image_slot *slot = mg_image_find(handle);
    if (!mg_image_arguments(slot, x, y, w, h, alpha)) return false;
    mg_vector_target host = mg_get_vector_target(); cairo_t *cr = host.context; if (!cr) return false;
    if (!slot->resource) slot->resource = cairo_image_surface_create_for_data((unsigned char *)slot->pixels,
        CAIRO_FORMAT_ARGB32, slot->width, slot->height, slot->width * 4);
    if (cairo_surface_status(slot->resource) != CAIRO_STATUS_SUCCESS) return false;
    cairo_save(cr); cairo_translate(cr, x, y); cairo_scale(cr, w / slot->width, h / slot->height);
    cairo_rectangle(cr, 0, 0, slot->width, slot->height); cairo_clip(cr);
    cairo_set_source_surface(cr, slot->resource, 0, 0); cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BILINEAR);
    cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
    cairo_paint_with_alpha(cr, alpha); cairo_restore(cr); return cairo_status(cr) == CAIRO_STATUS_SUCCESS;
}
