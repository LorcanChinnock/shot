// Reads a ScreenCast portal's PipeWire video node in shared memory, for ShotCoreLinux to record. It's C because Swift
// can't import the SPA macros that build a stream's parameters.

#include "shot_pipewire.h"

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/buffer/meta.h>

struct shot_pw_stream {
    struct pw_thread_loop *loop;
    struct pw_context *context;
    struct pw_core *core;
    struct pw_stream *stream;
    struct spa_hook core_listener;
    struct spa_hook stream_listener;
    struct spa_video_info_raw format;
    shot_pw_format layout;
    bool has_format;
    bool streamed;
    bool ended;
    bool stopping;
    shot_pw_frame_fn on_frame;
    shot_pw_end_fn on_end;
    void *context_pointer;
};

// On the stream's thread, with the loop locked.
static void end(struct shot_pw_stream *stream, const char *reason) {
    if (stream->ended || stream->stopping) {
        return;
    }
    stream->ended = true;
    stream->on_end(stream->context_pointer, reason);
}

static void on_core_error(void *data, uint32_t id, int seq, int res, const char *message) {
    (void)seq;
    (void)res;
    if (id == PW_ID_CORE) {
        end(data, message ? message : "PipeWire closed the connection");
    }
}

static const struct pw_core_events core_events = {
    PW_VERSION_CORE_EVENTS,
    .error = on_core_error,
};

static void on_state_changed(void *data, enum pw_stream_state old, enum pw_stream_state state, const char *error) {
    (void)old;
    struct shot_pw_stream *stream = data;
    switch (state) {
    case PW_STREAM_STATE_ERROR:
        end(stream, error ? error : "the screen cast's stream failed");
        break;
    case PW_STREAM_STATE_UNCONNECTED:
        end(stream, "the screen cast ended");
        break;
    case PW_STREAM_STATE_STREAMING:
        stream->streamed = true;
        break;
    default:
        break;
    }
}

static void on_param_changed(void *data, uint32_t id, const struct spa_pod *param) {
    struct shot_pw_stream *stream = data;
    if (param == NULL || id != SPA_PARAM_Format) {
        return;
    }
    uint32_t media_type, media_subtype;
    if (spa_format_parse(param, &media_type, &media_subtype) < 0 || media_type != SPA_MEDIA_TYPE_video || media_subtype != SPA_MEDIA_SUBTYPE_raw) {
        return;
    }
    struct spa_video_info_raw format;
    spa_zero(format);
    if (spa_format_video_raw_parse(param, &format) < 0) {
        return;
    }
    switch (format.format) {
    case SPA_VIDEO_FORMAT_BGRx: stream->layout = SHOT_PW_BGRX; break;
    case SPA_VIDEO_FORMAT_BGRA: stream->layout = SHOT_PW_BGRA; break;
    case SPA_VIDEO_FORMAT_RGBx: stream->layout = SHOT_PW_RGBX; break;
    case SPA_VIDEO_FORMAT_RGBA: stream->layout = SHOT_PW_RGBA; break;
    default:
        end(stream, "the screen cast offered no pixel format Shot can read");
        return;
    }
    stream->format = format;
    stream->has_format = true;

    // Shared memory only: mapped by PipeWire, or a memfd it maps for us, never DMA-BUF, which needs a GPU to read.
    uint8_t buffer[1024];
    struct spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    const struct spa_pod *params[2];
    params[0] = spa_pod_builder_add_object(
        &builder, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
        SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(8, 2, 16),
        SPA_PARAM_BUFFERS_blocks, SPA_POD_Int(1),
        SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int((1 << SPA_DATA_MemPtr) | (1 << SPA_DATA_MemFd)));
    // Window casts may send a whole buffer with the window's part of it marked.
    params[1] = spa_pod_builder_add_object(
        &builder, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
        SPA_PARAM_META_type, SPA_POD_Id(SPA_META_VideoCrop),
        SPA_PARAM_META_size, SPA_POD_Int(sizeof(struct spa_meta_region)));
    pw_stream_update_params(stream->stream, params, 2);
}

static void on_process(void *data) {
    struct shot_pw_stream *stream = data;
    // Only the newest frame, handing back any older ones still queued.
    struct pw_buffer *newest = NULL, *next;
    while ((next = pw_stream_dequeue_buffer(stream->stream)) != NULL) {
        if (newest != NULL) {
            pw_stream_queue_buffer(stream->stream, newest);
        }
        newest = next;
    }
    if (newest == NULL) {
        return;
    }
    struct spa_buffer *buffer = newest->buffer;
    struct spa_data *plane = &buffer->datas[0];
    if (stream->has_format && !stream->stopping && plane->data != NULL && plane->chunk->size > 0 && !(plane->chunk->flags & SPA_CHUNK_FLAG_CORRUPTED)) {
        uint32_t x = 0, y = 0, width = stream->format.size.width, height = stream->format.size.height;
        uint32_t stride = plane->chunk->stride > 0 ? (uint32_t)plane->chunk->stride : width * 4;
        struct spa_meta_region *crop = spa_buffer_find_meta_data(buffer, SPA_META_VideoCrop, sizeof(*crop));
        if (crop != NULL && spa_meta_region_is_valid(crop) && crop->region.position.x >= 0 && crop->region.position.y >= 0
            && (uint32_t)crop->region.position.x + crop->region.size.width <= width && (uint32_t)crop->region.position.y + crop->region.size.height <= height) {
            x = (uint32_t)crop->region.position.x;
            y = (uint32_t)crop->region.position.y;
            width = crop->region.size.width;
            height = crop->region.size.height;
        }
        uint64_t offset = plane->chunk->offset % (plane->maxsize > 0 ? plane->maxsize : 1);
        uint64_t first = offset + (uint64_t)y * stride + (uint64_t)x * 4;
        bool fits = width > 0 && height > 0 && stride >= width * 4 && first + (uint64_t)(height - 1) * stride + (uint64_t)width * 4 <= plane->maxsize;
        if (fits) {
            stream->on_frame(stream->context_pointer, (const uint8_t *)plane->data + first, width, height, stride, stream->layout);
        }
    }
    pw_stream_queue_buffer(stream->stream, newest);
}

static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .state_changed = on_state_changed,
    .param_changed = on_param_changed,
    .process = on_process,
};

static void destroy(struct shot_pw_stream *stream) {
    if (stream->loop != NULL) {
        pw_thread_loop_stop(stream->loop);
    }
    if (stream->stream != NULL) {
        spa_hook_remove(&stream->stream_listener);
        pw_stream_destroy(stream->stream);
    }
    if (stream->core != NULL) {
        spa_hook_remove(&stream->core_listener);
        pw_core_disconnect(stream->core);
    }
    if (stream->context != NULL) {
        pw_context_destroy(stream->context);
    }
    if (stream->loop != NULL) {
        pw_thread_loop_destroy(stream->loop);
    }
    free(stream);
}

shot_pw_stream *shot_pw_stream_start(int fd, uint32_t node, uint32_t frame_rate, shot_pw_frame_fn on_frame, shot_pw_end_fn on_end, void *context,
                                     char *error, size_t error_size) {
    pw_init(NULL, NULL);
    struct shot_pw_stream *stream = calloc(1, sizeof(*stream));
    if (stream == NULL) {
        close(fd);
        snprintf(error, error_size, "out of memory");
        return NULL;
    }
    stream->on_frame = on_frame;
    stream->on_end = on_end;
    stream->context_pointer = context;
    stream->loop = pw_thread_loop_new("shot-pipewire", NULL);
    if (stream->loop == NULL) {
        close(fd);
        snprintf(error, error_size, "couldn't make PipeWire's thread: %s", strerror(errno));
        destroy(stream);
        return NULL;
    }
    stream->context = pw_context_new(pw_thread_loop_get_loop(stream->loop), NULL, 0);
    if (stream->context == NULL) {
        close(fd);
        snprintf(error, error_size, "couldn't start PipeWire: %s", strerror(errno));
        destroy(stream);
        return NULL;
    }
    if (pw_thread_loop_start(stream->loop) < 0) {
        close(fd);
        snprintf(error, error_size, "couldn't start PipeWire's thread");
        destroy(stream);
        return NULL;
    }
    pw_thread_loop_lock(stream->loop);
    // It takes the fd, and closes it on failure too. Only a connection through the portal's fd sees the screen cast's
    // node, since WirePlumber hides it from the rest.
    stream->core = pw_context_connect_fd(stream->context, fd, NULL, 0);
    if (stream->core == NULL) {
        snprintf(error, error_size, "couldn't connect to PipeWire: %s", strerror(errno));
        pw_thread_loop_unlock(stream->loop);
        destroy(stream);
        return NULL;
    }
    pw_core_add_listener(stream->core, &stream->core_listener, &core_events, stream);
    stream->stream = pw_stream_new(stream->core, "Shot",
                                   pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY, "Capture", PW_KEY_MEDIA_ROLE, "Screen", NULL));
    if (stream->stream == NULL) {
        snprintf(error, error_size, "couldn't make a PipeWire stream: %s", strerror(errno));
        pw_thread_loop_unlock(stream->loop);
        destroy(stream);
        return NULL;
    }
    pw_stream_add_listener(stream->stream, &stream->stream_listener, &stream_events, stream);

    // No modifiers, so the formats are offered in shared memory only.
    uint8_t buffer[1024];
    struct spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    const struct spa_pod *params[1];
    params[0] = spa_pod_builder_add_object(
        &builder, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format, SPA_POD_CHOICE_ENUM_Id(5, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRA, SPA_VIDEO_FORMAT_RGBx, SPA_VIDEO_FORMAT_RGBA),
        SPA_FORMAT_VIDEO_size, SPA_POD_CHOICE_RANGE_Rectangle(&SPA_RECTANGLE(1920, 1080), &SPA_RECTANGLE(1, 1), &SPA_RECTANGLE(16384, 16384)),
        SPA_FORMAT_VIDEO_framerate, SPA_POD_CHOICE_RANGE_Fraction(&SPA_FRACTION(frame_rate, 1), &SPA_FRACTION(0, 1), &SPA_FRACTION(360, 1)));
    int connected = pw_stream_connect(stream->stream, PW_DIRECTION_INPUT, node, PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, params, 1);
    pw_thread_loop_unlock(stream->loop);
    if (connected < 0) {
        snprintf(error, error_size, "couldn't read the screen cast's stream: %s", strerror(-connected));
        destroy(stream);
        return NULL;
    }
    return stream;
}

void shot_pw_stream_stop(shot_pw_stream *stream) {
    if (stream == NULL) {
        return;
    }
    pw_thread_loop_lock(stream->loop);
    stream->stopping = true;
    pw_stream_disconnect(stream->stream);
    pw_thread_loop_unlock(stream->loop);
    destroy(stream);
}

const char *shot_pw_library_version(void) {
    return pw_get_library_version();
}
