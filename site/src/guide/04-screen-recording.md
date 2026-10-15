---
title: Screen recording
summary: "Record an area, a window or the whole screen, with your voice, the sound from your Mac and your camera."
group: Capture
---

![The recording controls: elapsed time, Pause, the camera bubble, discard and Stop](../../../docs/media/recording-controls.png)

Press ⌘⇧5, then drag out an area (the magnifier helps here too), press Space and click a window, or press Return for the full screen. Recording starts as soon as you let go, with the camera bubble, microphone and cursor set as in **Settings › Recording**. Record Full Screen and Record Window start on their own shortcuts, once you set them.

To adjust first, hold ⌥ as you finish the selection, or turn on **Adjust before recording** in **Settings › Recording** to do it every time. You can then adjust the frame, switch between area, screen and window, and turn the camera bubble, microphone and cursor on or off for this recording. Press Return or click **Record** to start, or Esc to cancel. **Countdown** in the same settings adds a 3 or 5 second countdown before recording starts, with or without this step. Esc during the countdown goes back to the adjust step if it was shown, and otherwise cancels the recording.

If you picked the area with a ratio (Tab or Shift), the frame's handles keep it.

A window recording captures just that window: it follows the window when it moves and leaves out anything on top of it. It has no camera bubble, and dragging the frame turns it into an area recording.

While recording, the controls let you pause and resume, stop and save, and discard the recording; for 5 seconds after a discard, **Undo** brings it back, and so does ⌘Z, whichever app is in front. With the microphone on, they also show its level and a button to mute it, which silences only the microphone. With the camera bubble on, they show, hide or resize it. The menu bar menu has **Pause Recording** (or **Resume Recording**) and **Stop Recording** too. On a Mac with a notch, when there's no room for the controls outside the recorded area, they move into the notch: a black pill shows the elapsed time, and hovering it shows the controls. Pressing any record shortcut again, or opening `shot://record`, stops the recording. Quitting Shot while it records stops and saves the recording first. If Shot crashes mid-recording, or the pieces can't be joined, the next launch (or the failed stop) saves what was recorded to your save folder as `… (recovered).mp4`, or as separate `(recovered, part N)` files, and shows a toast with **Show**. A recording that ran out of disk space keeps its last part if that part still plays.

Recordings are H.264 MP4 at 30 or 60 fps. Each stretch between pauses is written to a temporary folder as it records, and they're joined into one file in your save folder when you stop. With a display that refreshes at 120 Hz or faster, such as a ProMotion MacBook Pro, **Settings › Recording** also offers 120 fps. A 120 fps recording, and its export from the video editor, is HEVC MP4. On a slower screen, a 120 fps recording drops to 60 fps. When a recording finishes, Shot copies the file to the clipboard unless you turn off **Copy to clipboard** in **Settings › Recording**, and shows it in [Quick Access](#quick-access) unless you turn that off in **Settings › Capture**. A recording never opens in the video editor by itself. In **Settings › Recording** you can also show the cursor, turn on **Show clicks** to draw a circle at each click, outline the recorded area with **Region border** (the border never appears in the video), and record your microphone and system audio. System audio is sound from other apps; Shot's own sounds are left out.

## Camera bubble

A round webcam overlay that is recorded with your screen. It starts in the bottom-left corner of the recorded area, and stays inside it. Drag it to move it, and double-click it to step through small, medium and large; the size you pick becomes the default. Pick the camera and the size in **Settings › Recording**. A window recording has no camera bubble, and an area too small for the bubble records without it.

macOS asks for Microphone and Camera access the first time Shot uses them.
