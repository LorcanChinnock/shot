---
title: Edit a recording
summary: "Trim, cut, split, crop and add clips to a recording, then save it."
group: Edit and share
aliases: [video-editor]
---

![The video editor timeline with a text label and an arrow on their own lanes, the arrow's Pop keyframes, a trimmed start, a cut, the Inspector and the GIF export options](../../../docs/media/video-timeline.png)

## Open the video editor

- **Edit** on a recording's [Quick Access](#quick-access) card.
- **Edit Video** in the [gallery](#find-your-captures), or a double-click on the recording there.
- A [`shot://edit-video?path=…`](#url-scheme) link.

## Play and move around

| Press | To |
|---|---|
| <kbd>Space</kbd> | Play or pause. |
| <kbd>←</kbd> <kbd>→</kbd> | Step one frame. |
| <kbd>⇧←</kbd> <kbd>⇧→</kbd> | Step one second. |
| <kbd>Home</kbd> <kbd>End</kbd> | Go to the start or the end. |

Click the ruler to move the playhead. Pinch, or press <kbd>⌘+</kbd> and <kbd>⌘−</kbd>, to zoom the timeline, and click **Fit** or press <kbd>⌘0</kbd> to fit it to the window.

## Trim the ends

Drag the yellow handles at either end of the main track. What you trim off stays greyed out, so you can drag it back.

### Trim idle time

Most recordings start with a few seconds of reaching for the mouse and end with a few of reaching for Stop. Choose **Edit › Trim Idle Time** and Shot moves both handles to where things start and stop changing on screen, with a little time to spare either side. Anything you say stays in, even over a still screen.

- It's one step, so <kbd>⌘Z</kbd> puts the handles back.
- It only moves the handles in, so anything you've already trimmed off stays off.
- It compares frames on your Mac. Nothing is uploaded, and a pointer moving over a still screen counts as idle.
- It works while your edit is only trims and cuts of one recording.

## Cut out a section

1. Hold <kbd>Shift</kbd> and drag along the timeline to select a section.
2. Press <kbd>Delete</kbd>.

## Split and rearrange

- **Split** (<kbd>S</kbd>) splits the clips under the playhead.
- **Delete** (<kbd>⌫</kbd>) cuts out the selected clip and closes the gap.
- **Snap** (<kbd>N</kbd>) snaps the playhead, and clips you drag or trim, to clip edges and the playhead.
- **Tracks** (<kbd>T</kbd>) shows or hides the tracks. Once your edit is more than trims and cuts, they stay shown.

## Add video or sound

- **Import › Add Video or Audio at Playhead…**, or dropping a file on the window, puts its picture on a new lane above the main track and its sound on a lane of its own.
- **Import › Add Video to End…** adds a video to the end of the main track.

Drag a clip on another lane to move it in time, or drag its edges to trim it. Sound lanes show a waveform, which grows and shrinks with the clip's volume.

## Move, scale and rotate a clip

Select a clip, the recording included, while the playhead is on it, and a yellow box appears over the video:

- Drag inside the box to move the clip.
- Drag a corner to scale it about its centre.
- Drag the pink knob above it to rotate it.

## Crop the video

- **The whole video:** with nothing selected, press <kbd>C</kbd>, or click **Crop** under **Frame** in the Inspector.
- **One clip:** select it and press <kbd>C</kbd>, double-click its yellow box, or click **Crop** in the Inspector.

Cropping works as in the [annotation editor](#crop): what's cropped off shows dimmed, drag a handle to resize or inside to move, hold <kbd>Shift</kbd> to keep the shape, and pick an **Aspect** (Free, 1:1, 4:3 or 16:9). **Reset** shows everything again. <kbd>Return</kbd> or **Apply** applies the crop as one undo step, and <kbd>Esc</kbd> or **Cancel** leaves it as it was.

- **Cropping the video changes its size.** Cropping off the menu bar of a 1920 × 1080 recording gives a smaller video, not a scaled-up one, and MP4 and GIF exports come out at the cropped size. Sizes round down to even numbers. The Inspector shows the size under **Frame**, with **Reset** to take the crop off.
- **A cropped clip** still moves, scales and turns as a whole, about the middle of its whole picture, and its corners, shadow and border follow the cropped edge. **Reset Crop** in the Inspector shows all of it again.

> [!TIP]
> Crops aren't animated. For a zoom over time, [animate](#animate-and-annotate-a-recording) the clip's scale and position.

## Undo, delete and cancel

- <kbd>⌘Z</kbd> undoes and <kbd>⇧⌘Z</kbd> redoes.
- <kbd>Delete</kbd> takes away the selected keyframe, or else the selected section, or else the selected clip or annotation.
- <kbd>Esc</kbd> cancels an export, or else clears the selected section, or else deselects, or else stops annotating.

## Save

**Save** (<kbd>⌘S</kbd>) replaces the recording with your trimmed version, without re-encoding where it can, and copies it. The title shows **TRIMMED** while you've only trimmed the ends, and **EDITED** once there's a cut or more.

Once your edit is more than trims and cuts, the button reads **Save Copy** instead, and writes a new file next to the recording. An import, annotation, keyframe or crop, a moved or styled recording, a changed volume, reordered clips, or a hidden or muted track each switches it to **Save Copy**.

**Copy** (<kbd>⌘C</kbd>) copies the edited video, everything included. To make an MP4 or GIF with other settings, see [Export a video or GIF](#export-a-video-or-gif).

Closing the window asks whether to save, or to save a copy, when you've changed anything since you last saved, saved a copy or exported.
