#ifndef MYGOOSE_IMAGE_H
#define MYGOOSE_IMAGE_H
#include "../../../native/vector_target.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
/* Shared storage is allocated only for uploaded images. Stale handles cannot
   refer to a reused slot. 128 images, 64 MiB total, 4096 pixels per dimension. */
typedef struct {
    int64_t id; int width, height; uint32_t *pixels;
    void *resource, *secondary, *owner;
} mg_image_slot;
static mg_image_slot mg_images[128];
static int64_t mg_image_next;
static size_t mg_image_bytes;
static void mg_image_release(mg_image_slot *slot);
static mg_image_slot *mg_image_find(int64_t handle) {
    if (handle <= 0) return NULL;
    for (int i = 0; i < 128; ++i) if (mg_images[i].id == handle) return &mg_images[i];
    return NULL;
}
int64_t mg_image_create(mg_string rgba, int32_t width, int32_t height) {
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096 || mg_image_next == INT64_MAX) return 0;
    size_t bytes = (size_t)width * (size_t)height * 4;
    if (rgba.len != (int64_t)bytes || !rgba.data || bytes > 64 * 1024 * 1024 - mg_image_bytes) return 0;
    for (int i = 0; i < 128; ++i) if (!mg_images[i].id) {
        uint32_t *pixels = malloc(bytes); if (!pixels) return 0;
        for (size_t n = 0; n < bytes / 4; ++n) {
            const uint8_t *p = rgba.data + n * 4; unsigned a = p[3];
            pixels[n] = (a << 24) | (((p[0] * a + 127) / 255) << 16) | (((p[1] * a + 127) / 255) << 8) | ((p[2] * a + 127) / 255);
        }
        mg_images[i] = (mg_image_slot){ .id = ++mg_image_next, .width = width, .height = height, .pixels = pixels };
        mg_image_bytes += bytes; return mg_images[i].id;
    }
    return 0;
}
void mg_image_free(int64_t handle) {
    mg_image_slot *slot = mg_image_find(handle); if (!slot) return;
    mg_image_release(slot); mg_image_bytes -= (size_t)slot->width * (size_t)slot->height * 4;
    free(slot->pixels); memset(slot, 0, sizeof *slot);
}
static bool mg_image_arguments(mg_image_slot *slot, float x, float y, float w, float h, float alpha) {
    return slot && isfinite(x) && isfinite(y) && isfinite(w) && isfinite(h) && isfinite(alpha) &&
        fabsf(x) <= 1000000 && fabsf(y) <= 1000000 && w > 0 && h > 0 && w <= 1000000 && h <= 1000000 && alpha >= 0 && alpha <= 1;
}
bool mg_image_draw(int64_t handle, float x, float y, float w, float h, float alpha);
bool mg_image_paint(mg_string data, float x, float y, float w, float h) {
    if (data.len != 12 || !data.data) return false;
    int64_t handle; float alpha;
    memcpy(&handle, data.data, 8); memcpy(&alpha, data.data + 8, 4);
    return mg_image_draw(handle, x, y, w, h, alpha);
}
#endif
