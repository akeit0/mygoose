/* Optional modules query the current backend's opaque drawing target.
   No storage or renderer dependency is added to a basic application. */
#ifndef MYGOOSE_VECTOR_TARGET_H
#define MYGOOSE_VECTOR_TARGET_H
#include "backend.h"
typedef struct {
    void *context, *factory, *target, *brush;
    uint32_t *pixels;
    int width,height,renderer;
    float scale;
} mg_vector_target;
mg_vector_target mg_get_vector_target(void);
#endif
