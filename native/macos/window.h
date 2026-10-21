#ifndef MYGOOSE_MACOS_WINDOW_H
#define MYGOOSE_MACOS_WINDOW_H
#include <stdbool.h>
/* Optional AppKit adapters use an opaque NSWindow and a native event hook.
   No Objective-C types or callbacks enter the Goose UI core. */
void *mg_macos_window(void);
void mg_macos_defer_show(void);
void mg_macos_mouse_hook(bool (*hook)(void *event));
void mg_macos_dismiss_focus(void);
#endif
