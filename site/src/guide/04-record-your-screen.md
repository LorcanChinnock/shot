---
title: Record your screen
summary: "Record an area, a window or the whole screen, with your voice, the sound from your Mac and your camera."
group: Capture
aliases: [screen-recording]
---

![The recording controls: elapsed time, Pause, the camera bubble, discard and Stop](../../../docs/media/recording-controls.png)

## Start a recording

1. Press <kbd>⌘⇧5</kbd>.
2. Pick what to record:
   - **An area:** drag across it. The magnifier helps here too.
   - **A window:** press <kbd>Space</kbd>, then click the window.
   - **The whole screen:** press <kbd>Return</kbd>.
3. Recording starts as soon as you let go.

The camera bubble, microphone and cursor are on or off as you set them in **Settings › Recording**.

> [!TIP]
> **Record Full Screen** and **Record Window** can have shortcuts of their own. Set them in **Settings › Shortcuts**.

## Check everything before you start

Hold <kbd>⌥</kbd> as you finish picking an area or window. Before recording starts, you can then:

- move and resize the frame. If you picked an area with a ratio, the handles keep it.
- switch between an area, a screen and a window.
- turn the camera bubble, microphone and cursor on or off, just for this recording.

Press <kbd>Return</kbd> or click **Record** to start, or <kbd>Esc</kbd> to cancel. To get this step every time, turn on **Adjust before recording** in **Settings › Recording**.

**Countdown**, in the same settings, waits 3 or 5 seconds before recording starts. <kbd>Esc</kbd> during the countdown goes back to the adjust step if you had it, and cancels otherwise.

## While you record

The controls float beside the recorded area:

| Control | What it does |
|---|---|
| **Pause** | Pauses the recording. Click again to resume. |
| **Stop** | Stops and saves. |
| **Discard** | Throws the recording away. **Undo** brings it back for 5 seconds, and so does <kbd>⌘Z</kbd>, whichever app is in front. |
| **Microphone** | Shows its level, and mutes it. Muting silences only your microphone, not the sound from your Mac. |
| **Camera** | Shows, hides or resizes the camera bubble. |

You can also stop by pressing any record shortcut again. Shot's menu bar menu has **Pause Recording** (**Resume Recording** while paused) and **Stop Recording** too.

> [!NOTE]
> On a Mac with a notch, when there's no room for the controls outside the recorded area, they move into the notch: a black pill shows the elapsed time, and hovering it shows the controls.

## Record a window

A window recording captures just that window. It follows the window when you move it and leaves out anything on top of it. It has no camera bubble, and dragging its frame turns it into an area recording.

## Add your voice, your Mac's sound and your camera

In **Settings › Recording**:

- **Microphone** records your voice. Pick which microphone, and press **Test** to check it.
- **System audio** records the sound from other apps. Shot's own sounds are left out.
- **Camera bubble** adds a round webcam view to the recording. Pick the camera and size, and press **Preview** to check your framing.

The camera bubble starts in the bottom-left corner of the recorded area and stays inside it. Drag it to move it, and double-click it to step through small, medium and large. The size you pick becomes the default. An area too small for the bubble records without it.

macOS asks for microphone and camera access the first time Shot uses them. To allow both up front, click **Grant** beside each in **Settings › About**.

## Show the cursor and your clicks

Also in **Settings › Recording**:

- **Show cursor** records the pointer.
- **Show clicks** draws a circle wherever you click.
- **Region border** outlines the recorded area on screen while you record. The border never appears in the video.

## When you stop

Shot saves the recording to your save folder, copies it to the clipboard, and shows it in [Quick Access](#quick-access), where **Edit** opens it in the [video editor](#video-editor). It never opens the editor by itself.

To stop copying recordings, turn off **Copy to clipboard** in **Settings › Recording**. To skip the card, turn off **Show Quick Access** in **Settings › Capture**.

## Quality and file format

Recordings are H.264 MP4 at 30 or 60 frames per second. On a display that refreshes at 120 Hz or faster, such as a ProMotion MacBook Pro, **Settings › Recording** also offers 120 fps, which records HEVC MP4. Exports from the video editor of a 120 fps recording are HEVC too. On a slower screen, a 120 fps setting records at 60.

> [!NOTE]
> **If something goes wrong:** each stretch between pauses is written to a temporary folder as you record, and joined into one file when you stop. Quitting Shot mid-recording stops and saves it first. If Shot crashes, or the pieces can't be joined, Shot saves what it recorded to your save folder as `… (recovered).mp4`, or as separate `(recovered, part N)` files, and shows a message with **Show**. If the disk fills up, Shot keeps the last part if it still plays.

Every recording action has a [`shot://` link](#url-scheme) too, such as `shot://record`, which lets you pick an area to record, or stops the recording that's running.
