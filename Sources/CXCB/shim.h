#include <xcb/xcb.h>
#include <xcb/composite.h>
#include <xcb/randr.h>

// The extensions' IDs are mutable globals, which Swift 6 won't read from concurrent code.
static inline xcb_extension_t *shot_xcb_composite_id(void) { return &xcb_composite_id; }
static inline xcb_extension_t *shot_xcb_randr_id(void) { return &xcb_randr_id; }
