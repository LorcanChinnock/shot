#ifndef SHOT_PIPEWIRE_H
#define SHOT_PIPEWIRE_H

#include <stddef.h>
#include <stdint.h>

/// The pixel layouts a stream is asked for, four bytes a pixel, in the order of their bytes; x is unused.
typedef enum {
    SHOT_PW_BGRX = 0,
    SHOT_PW_BGRA = 1,
    SHOT_PW_RGBX = 2,
    SHOT_PW_RGBA = 3,
} shot_pw_format;

/// Called on the stream's thread with each frame's rows, `stride` bytes apart, which last only until it returns.
typedef void (*shot_pw_frame_fn)(void *context, const uint8_t *pixels, uint32_t width, uint32_t height, uint32_t stride, shot_pw_format format);
/// Called on the stream's thread, once, when the stream fails or the screen cast ends, with why.
typedef void (*shot_pw_end_fn)(void *context, const char *reason);

typedef struct shot_pw_stream shot_pw_stream;

/// Connects to PipeWire through `fd`, which the ScreenCast portal's OpenPipeWireRemote gave and which this closes, and
/// reads the video node `node` in shared memory on a thread of its own, at up to `frame_rate` frames a second. Returns
/// `NULL`, with why in `error`, when it can't.
shot_pw_stream *shot_pw_stream_start(int fd, uint32_t node, uint32_t frame_rate, shot_pw_frame_fn on_frame, shot_pw_end_fn on_end, void *context,
                                     char *error, size_t error_size);

/// Stops reading and frees the stream. Neither callback is called once it returns. Never call it from a callback.
void shot_pw_stream_stop(shot_pw_stream *stream);

/// The version of libpipewire that's loaded, such as "1.0.5".
const char *shot_pw_library_version(void);

#endif
