#include "../../../native/backend.h"
#include <math.h>
#include <string.h>
#include <stdio.h>

static uint32_t mg_ch_tint(uint32_t front, uint32_t back, unsigned alpha) {
    uint32_t color = 0;
    for (unsigned shift = 0; shift < 24; shift += 8)
        color |= ((((front >> shift) & 255) * alpha + ((back >> shift) & 255) * (255 - alpha)) / 255) << shift;
    return color;
}
static mg_string mg_ch_chart_string(const char *s) { return (mg_string){(const uint8_t *)s, (int64_t)strlen(s)}; }
#ifndef MG_CH_ARC
/* Portable arc fallback for backends without a chart renderer. */
static void mg_ch_arc(float cx,float cy,float radius,float thickness,float amount,uint32_t color) {
    const float pi = 3.14159265358979323846f;
    float arc = amount * 2 * pi;
    int steps = (int)ceilf(arc * radius / fmaxf(.5f, thickness * .2f));
    if (steps < 1) steps = 1;
    for (int i = 0; i <= steps; ++i) {
        float angle = -pi / 2 + arc * i / steps;
        mg_rect(cx + radius * cosf(angle) - thickness / 2, cy + radius * sinf(angle) - thickness / 2,
            thickness, thickness, thickness / 2, color);
    }
}
#define MG_CH_ARC mg_ch_arc
#endif
/* Chart renderers own native shape drawing; payload, geometry and labels
   remain shared. No retained textures, vector dependency or core storage. */
static void mg_ch_ring(float x, float y, float w, float h, float ratio, uint32_t color, const uint32_t *palette) {
    float size = fminf(w, h) - 4, outer = size / 2, thickness = fmaxf(7, fminf(11, size * .10f)), inner = outer - thickness;
    float cx = w / 2, cy = h / 2, amount = fminf(1, fmaxf(0, ratio));
    mg_rect(x + cx - outer, y + cy - outer, size, size, outer, palette[1]);
    mg_rect(x + cx - inner, y + cy - inner, inner * 2, inner * 2, inner, palette[0]);
    if (amount > 0) MG_CH_ARC(x + cx,y + cy,(outer + inner) / 2,thickness,amount,color);
    char label[32]; snprintf(label, sizeof label, "%.0f%%", ratio * 100);
    mg_string text = mg_ch_chart_string(label); float font = size < 90 ? 16 : 21;
    mg_text(text, x + cx - mg_measure(text, font, true) / 2, y + cy - font * .6f, font, true, palette[2]);
}
/* Validation precedes all drawing. Payloads are scene-owned, contain no
   pointers, and participate in the normal damage hash. Maximum 180 columns. */
bool mg_chart(mg_string data, float x, float y, float width, float height) {
    if (!data.data || data.len < 40 || !isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        fabsf(x) > 1000000 || fabsf(y) > 1000000 || width < 1 || height < 1 || width > 16384 || height > 16384) return false;
    uint32_t header[4], palette[4]; float scale; int32_t span;
    memcpy(header, data.data, 16); memcpy(palette, data.data + 16, 16); memcpy(&scale, data.data + 32, 4); memcpy(&span, data.data + 36, 4);
    uint32_t kind = header[0], color = header[1], second = header[2], columns = header[3];
    if (kind > 3 || color > 0xffffff || second > 0xffffff || !isfinite(scale) || scale < 0 || scale > 1e15f) return false;
    for (unsigned i = 0; i < 4; ++i) if (palette[i] > 0xffffff) return false;
    if (kind == 1 || kind == 2) {
        if (columns || data.len != 40 || (kind == 1 && (width < 24 || height < 24))) return false;
        if (kind == 1) mg_ch_ring(x, y, width, height, scale, color, palette);
        else {
            mg_rect(x, y, width, height, height / 2, palette[1]);
            float filled = fminf(scale, 1) * width;
            if (filled > 0) mg_rect(x, y, filled, height, height / 2, color);
        }
        return true;
    }
    if (columns < 1 || columns > 180 || data.len != 40 + columns * 8 || scale <= 0 || span < 1 || span > 3600 || width < 32 || height < 24) return false;
    float values[360]; memcpy(values, data.data + 40, columns * 8);
    for (unsigned i = 0; i < columns * 2; ++i) if (!isfinite(values[i]) || values[i] < -1 || values[i] > 1e15f) return false;
    uint32_t background = mg_ch_tint(color, palette[0], 24), dim = mg_ch_tint(color, background, 42);
    mg_rect(x, y, width, height, 10, background);
    bool axes = height >= 100; float plot = height - (axes ? 36 : 16);
    if (kind == 3) {
        // One slot per supplied sample. Keep the timeline independent of
        // window width: append on the right and shift old samples left.
        float dx = (width - 24) / columns, gap = fminf(1.5f, dx * .24f);
        for (unsigned col = 0; col < columns; ++col) {
            float a = fmaxf(0, values[col * 2]), b = fmaxf(0, values[col * 2 + 1]);
            float low = fminf(1, b / scale) * plot;
            float high = fminf(1, (a + b) / scale) * plot;
            float left = x + 12 + col * dx + gap / 2, baseline = y + 8 + plot;
            if (low > 0) mg_rect(left, baseline - low, dx - gap, low, 0, second);
            if (high > low) mg_rect(left, baseline - high, dx - gap, high - low, 0, color);
        }
    } else {
        unsigned display = (unsigned)fmaxf(12, fminf(180, floorf((width - 24) / 8)));
        float dx = (width - 24) / display;
        int rows = (int)fmaxf(3, fminf(24, floorf(plot / 8))); float dy = plot / rows;
        float dot = fminf(4.4f, fminf(dx, dy) * .64f);
        for (unsigned col = 0; col < display; ++col) {
            unsigned sample = (col * (columns - 1) + (display - 1) / 2) / (display - 1);
            float a = values[sample * 2], b = values[sample * 2 + 1];
            int low = b <= 0 ? 0 : (int)ceilf(fminf(1, b / scale) * rows);
            int high = (int)ceilf(fminf(1, (fmaxf(0, a) + fmaxf(0, b)) / scale) * rows);
            for (int row = 0; row < rows; ++row) {
                uint32_t tint = a < 0 && b < 0 ? dim : row < low ? second : row < high ? color : dim;
                mg_rect(x + 12 + (col + .5f) * dx - dot / 2, y + 8 + (rows - row - .5f) * dy - dot / 2, dot, dot, dot / 2, tint);
            }
        }
    }
    if (axes) for (int i = 0; i < 5; ++i) {
        char label[32]; int seconds = span * (4 - i) / 4;
        if (!seconds) strcpy(label, "now");
        else if (seconds >= 60 && seconds % 60 == 0) snprintf(label, sizeof label, "-%dm", seconds / 60);
        else snprintf(label, sizeof label, "-%ds", seconds);
        mg_string text = mg_ch_chart_string(label); float measured = mg_measure(text, 10, false);
        mg_text(text, x + 12 + (width - 24 - measured) * i / 4, y + height - 20, 10, false, palette[3]);
    }
    return true;
}
