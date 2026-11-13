---
title: Keyboard shortcuts
summary: "Every shortcut in Shot, and how to change them."
group: Reference
---

## Global

These work in any app, while Shot is running:

| Shortcut | Action |
|---|---|
| <kbd>⌘⇧4</kbd> | Take a screenshot. Press <kbd>Tab</kbd> to pick an area, a window or the full screen. |
| <kbd>⌘⇧5</kbd> | Record. Press <kbd>Tab</kbd> to pick an area, a window or the full screen. |

While you set up a recording, the record shortcut starts it. While you record, it stops the recording.

Shot takes these keys over from macOS while it runs, once it has Screen Recording access, unless you turned that off in the [welcome window](#follow-the-welcome-window). When Shot quits, macOS gets its keys back.

## Change a shortcut

1. Open **Settings › Shortcuts**.
2. Under **Global**, click a shortcut. It says **Press keys…** while it waits.
3. Press the new keys. They must include <kbd>⌘</kbd>, <kbd>⌥</kbd> or <kbd>⌃</kbd>. <kbd>Esc</kbd> cancels, and <kbd>Delete</kbd> clears the shortcut, which then says **Record Shortcut**.

Shot won't take a shortcut that another action already uses, or <kbd>⌘Q</kbd>, <kbd>⌘W</kbd>, <kbd>⌘Tab</kbd>, <kbd>⌘Space</kbd>, <kbd>⌘H</kbd> or <kbd>⌘M</kbd>. **Restore Defaults**, at the top right of the window, puts them all back and turns **Use Shot for ⌘⇧4 and ⌘⇧5** back on.

Under **While picking what to capture**, the same pane lists the main keys from [While selecting](#while-selecting).

## Keep the macOS screenshot tool

Turn off **Use Shot for ⌘⇧4 and ⌘⇧5** in **Settings › Shortcuts**. macOS gets its keys back, and Shot uses the same keys with <kbd>⌃</kbd> in place of <kbd>⌘</kbd>: <kbd>⌃⇧4</kbd> and <kbd>⌃⇧5</kbd>.

> [!NOTE]
> If you turn the macOS shortcuts back on in System Settings, Shot stops using those keys until you turn **Use Shot for ⌘⇧4 and ⌘⇧5** on again.

## Actions you can give a shortcut

**Pick Colour** is in the menu bar menu only. Every action also has a [`shot://` link](#url-scheme).

- **Pick Colour** shows a loupe with the colour under the pointer and its hex. Click any pixel on screen to copy the hex, such as `#1E90FF`. To land on an exact pixel, move with the arrow keys and press Return. Esc cancels.

## Scrolling capture

| Key | Action |
|---|---|
| Return | Save and copy the picture so far |
| Esc | Cancel, keeping nothing |

These work while the content's app has the keyboard, so you can keep scrolling with <kbd>Page Down</kbd> or <kbd>Space</kbd>. The screenshot shortcut also finishes the capture.

## While selecting

| Key | Action |
|---|---|
| Tab | Switch between picking an area, a window and the full screen. <kbd>⇧Tab</kbd> goes back. |
| D | Step the delay through Off, 3, 5 and 10 seconds. |
| R | Step the area's ratio. |
| X | Turn the area's ratio between landscape and portrait. |
| B | Turn **Leave out browser toolbars** on or off for this capture. While it's on, clicking a browser window captures just its page, and any other window is captured whole. From Area or Full Screen it switches to Window with it on. |
| M | Turn the magnifier on or off for this capture. |
| C | Turn the crosshair guide lines on or off for this capture. |
| I | Turn the size label (the area's width and height in pixels) on or off for this capture. |
| Arrow keys | Make an area at the pointer, then move it. <kbd>⌥</kbd> and the arrow keys resize it. In window mode, step through the windows. |
| Space | Switch between picking an area and a window. While dragging an area, hold it to move the area. |
| S | Turn scrolling on or off, to build one screenshot of a long page. |
| Return | Take the highlighted window or screen, or the area you made with the keys. |
| ⌥ | Hold it as you finish picking what to record, to [check the frame and options](#record-your-screen) before recording starts. |
| Esc | Cancel |

## Recording setup

| Key | Action |
|---|---|
| Return | Start recording, after the delay if you set one |
| Esc | Cancel |

## Recording

| Key | Action |
|---|---|
| ⌘Z | Undo a discard, for 5 seconds after it, whichever app is in front |

## Annotation editor

| Key | Action |
|---|---|
| V H A L R D T S M F B N C | Choose a tool (see [Pick a tool](#pick-a-tool)) |
| Shift / Option while drawing | Keep it square or at 45° / draw from the centre |
| Shift / Option / Space while dragging a handle | Keep proportions or 45° (free on an image) / resize from the centre / move the shape |
| Delete | Delete the selection |
| Esc | Deselect, cancel what you're drawing, or finish typing |
| Return while typing | Start a new line |
| ⌘Return while typing | Finish typing |
| Arrow keys | Nudge the selection 1 pixel (10 with Shift) |
| Arrow keys on a focused slider or colour field | Step it by 1% (10% with Shift), stopping at the slider's notch on the way past. A held key is one undo step. Tab reaches sliders when Keyboard navigation is on in System Settings › Keyboard. |
| ⌘C | Copy the selected annotation, or the whole image |
| ⌘V | Paste an annotation or an image |
| ⌘D | Duplicate the selection |
| ⌥⌘C / ⌥⌘V | Copy / paste a style |
| ⇧⌘I | Add an image: a recent capture or a file |
| ⌘L | Show or hide the layers |
| ↑ / ↓ in the layers | Select the layer above or below. The Frame row, at the top while the image has a crop, takes up the crop tool. |
| Return in the layers | Rename the selected layer, or on the Frame row, hand the keys to the crop |
| ⌘] / ⌘[ | Move the selection forward / back |
| ⌥⌘] / ⌥⌘[ | Bring the selection to the front / send it to the back |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘+ / ⌘- | Zoom in / out |
| ⌘0 | Zoom to fit |
| ⌘1 | Actual size |
| Space-drag or middle-drag | Move around when zoomed in |
| ⌘S | Save and copy |
| ⌘W | Close, asking to save changes |

## Video editor

| Key | Action |
|---|---|
| Space | Play or pause |
| ← / → | Step back or forward one frame |
| ⇧← / ⇧→ | Step back or forward one second |
| Home / End | Go to the start / end |
| Shift-drag | Select a section of the timeline |
| S | Split the clips under the playhead |
| K | Key everything the selected clip or annotation can animate at the playhead, or take those keyframes away |
| N | Turn snapping on or off |
| ⌥⌘I | Show or hide the Inspector |
| C | Crop the selected clip, or the frame with nothing selected |
| Return | Apply the crop |
| Delete | Take away the selected keyframe, section, or clip or annotation; in crop mode, show everything again |
| Esc | Cancel a crop or an export, clear the selected section, deselect, stop annotating, or close the Export panel |
| ⌘] / ⌘[ | Move the selected annotation or clip a lane up / down |
| ⌥⌘] / ⌥⌘[ | Move the selected annotation or clip to the top / bottom lane |
| ⌘+ / ⌘− / ⌘0 | Zoom the timeline in / out / to fit |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘C | Copy the edited video |
| ⌥⌘C / ⌥⌘V | Copy / paste the selection's style |
| ⌘S | Save and copy |
| ⌘W | Close, asking to save changes |

## Gallery

| Keys | Action |
|---|---|
| Arrow keys, Home, End | Move the selection (⇧ extends it) |
| Return | Edit the selection |
| Space | Preview the selection, or go back to the grid |
| ← / → in the preview | Previous / next capture |
| ⌘A, ⌘⇧A | Select all, deselect all |
| ⌘C | Copy |
| ⌘R | Show in Finder |
| Delete | Move to the Trash, after asking |
| ⌘Delete | Move to the Trash without asking |
| ⌘Z | Put back what you last moved to the Trash |
| ⌘F | Search |
| ⌘+, ⌘− | Thumbnail size |
| Esc | Clear the selection, or go back to the grid from the preview |

## Any Shot window

| Key | Action |
|---|---|
| ⌘W | Close the window |
| ⌘, | Open Settings |
| ⌘Q | Quit Shot |
