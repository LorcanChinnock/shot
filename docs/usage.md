# Using Shot

The full guide to Shot. For a quick introduction, see the [README](../README.md).

- [Screenshots](#screenshots)
- [Quick Access](#quick-access)
- [Annotation editor](#annotation-editor)
- [Screen recording](#screen-recording)
- [Video editor](#video-editor)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [URL scheme](#url-scheme)
- [Settings](#settings)
- [Updates](#updates)
- [Privacy](#privacy)
- [Removing Shot](#removing-shot)

## Screenshots

- **Area (⌘⇧4):** the screen freezes, and you drag out an area. A magnifier next to the pointer helps you find exact edges. Hold Space while dragging to move the area. Press Esc to cancel.
- **Window:** press Space after ⌘⇧4, then click a window. Shot keeps the macOS window shadow unless you turn it off in Settings › Capture.
- **Fullscreen (⌘⇧3):** captures the screen under the pointer.

After a capture, Shot saves it, copies it, and shows it in [Quick Access](#quick-access). Choose which of these happen, or open the editor straight away, in **Settings › Capture**. Clipboard copies are always PNG.

## Quick Access

A floating card appears in a bottom corner of the screen after each capture. From the card you can:

- **Copy** or **Save As…**
- **Annotate** a screenshot, or **Edit** a recording in the [video editor](#video-editor)
- **Export GIF** from a recording. This uses the GIF frame rate and width you last chose in the video editor, and keeps the first 60 seconds.
- **Show in Finder**, or close the card
- Drag the card into another app, or onto an open editor to [combine images](#combine-images)

Cards close on their own after a few seconds; hovering a card pauses the timer. Pick the corner and the timer in **Settings › Quick Access**.

## Gallery

**Open Gallery** in the menu bar menu (or [`shot://gallery`](#url-scheme)) shows every screenshot, recording and GIF in your capture folder, grouped by day and kept up to date as you capture.

- **Filter** by All, Screenshots, Videos or GIFs, **search** by file name (⌘F), and **sort** by date, name or size. The slider (or ⌘+ and ⌘−) sets the thumbnail size.
- **Select** with a click, ⌘-click, ⇧-click, ⌘A or the arrow keys, or tick the checkbox on a thumbnail to add it to the selection. **Select All** and **Deselect All** sit next to the count at the bottom.
- **Edit** opens the selection, when none of it is a GIF, in the [annotation editor](#annotation-editor) or [video editor](#video-editor): double-click, press Return, or use the pencil/scissors button on a hovered thumbnail.
- **Quick Look** with Space.
- Right-click for **Export GIF** (a video), **Copy**, **Rename…**, **Show in Finder** and **Move to Trash**. Trashed files go to the Trash, so Finder can put them back.
- Drag a thumbnail into another app.

## Annotation editor

Open the editor from a Quick Access card, by turning on **Open in editor** in Settings › Capture, or with [`shot://annotate`](#url-scheme).

### Tools

Press a tool's key when you aren't typing text.

| Key | Tool |
|---|---|
| V | Select: move, resize and restyle what you've drawn |
| A | Arrow |
| L | Line |
| R | Shape: rectangle, rounded rectangle, ellipse, triangle, diamond or star |
| D | Freehand pen |
| T | Text |
| S | Sticky note |
| H | Highlight |
| F | Spotlight: dims or blurs everything outside the area |
| B | Redact: blurs or pixelates the area |
| N | Numbered counter |
| C | Crop |

Hover a tool to see what it does. Tools that draw a mark show a colour and one of three line widths below the tools; for text, sticky notes and counters the widths are text sizes, and changing the size or colour while you type updates the text as you go. The shape tool also offers the shape and a fill. Redact offers blur or pixelate. Spotlight offers its shape (rectangle, rounded or ellipse), whether to darken or blur outside it, and how strongly; the effect and strength apply to every spotlight in the image, since they share one dim. The editor remembers the last tool, colour, width and options you used.

### Editing annotations

- Click an annotation with the select tool to select it, then drag it, or drag its handles to resize it. Drag the middle handle of a line or arrow to bend it. Drag one of the round handles inside a rounded rectangle's corners to set how round all four are, up to a pill; they hide on a box too small to grab them. Choosing a colour, width or option restyles the selection.
- What you've just drawn stays selected until you draw the next thing, click elsewhere or press Esc, so you can fix its shape, colour, width or fill from the toolbar, or drag its handles, without switching to the select tool. The change also applies to what you draw next.
- Double-click text or a sticky note to edit it. Clicking a note with the note tool edits it too.
- Press Delete to remove the selection, and Esc to deselect. While you type in a text box or sticky note, Esc finishes it; ⌘Z removes it again.
- Arrow keys nudge the selection by 1 pixel, or 10 with Shift.
- ⌘C copies the selection, ⌘V pastes it, and ⌘D duplicates it. You can paste into another editor window. With nothing selected, ⌘C copies the whole image.
- ⌘Z undoes and ⇧⌘Z redoes.

### Canvas

Annotations can reach past the edges of the screenshot: the canvas grows to fit them. The **Canvas** menu fits the canvas to its content, trims it back to the image, and sets the background of the extra space to transparent (PNG only), white, or one of the palette colours.

### Combine images

Drag an image file or a Quick Access card onto the canvas, or press ⌘V with an image on the clipboard, to place another image beside your screenshot. A dropped image is centred where you drop it; a pasted one goes beside the canvas. Placed images keep their full resolution, keep their aspect ratio when you resize them, and can be moved, nudged, copied and deleted like any other annotation.

### Zoom

Pinch, or press ⌘+ and ⌘-, to zoom. ⌘0 fits the canvas to the window and ⌘1 shows it at actual size. When zoomed in, scroll or hold Space and drag to move around.

### Saving

**Copy** copies the annotated image. **Save** (⌘S) writes it beside the original as `name (2).png`, then `name (3).png` and so on, and copies it; the original is never changed. Closing the window with ⌘W asks whether to save unsaved changes.

## Screen recording

Press ⌘⇧5, then drag out an area, press Space and click a window, or press Enter for the full screen. Before recording, you can adjust the frame, switch between area, screen and window, and turn the camera bubble, microphone and cursor on or off. Press Return or click **Record** to start after a 3-second countdown, or Esc to cancel.

While recording, the controls let you pause and resume, stop and save, discard the recording, and show, hide or resize the camera bubble. On a Mac with a notch, when there's no room for the controls outside the recorded area, they move into the notch: a black pill shows the elapsed time, and hovering it shows the controls. Pressing the record shortcut again, or opening `shot://record`, stops the recording.

Recordings are H.264 MP4 at 30 or 60 fps. When a recording finishes, Shot copies the file to the clipboard and shows it in [Quick Access](#quick-access). In **Settings › Recording** you can also show the cursor, outline the recorded area (the outline never appears in the video), turn off copying, and record your microphone and system audio. System audio is sound from other apps; Shot's own sounds are left out.

### Camera bubble

A round webcam overlay that is recorded with your screen. Drag it to move it, and double-click it to change its size. Pick the camera and the default size (small, medium or large) in Settings › Recording.

macOS asks for Microphone and Camera access the first time you record with them.

## Video editor

Open a recording from its Quick Access card (**Edit**), or with [`shot://edit-video`](#url-scheme).

- **Trim:** drag the handles at either end of the timeline.
- **Cut:** Shift-drag on the timeline to select a section, then press Delete to cut it out. Esc clears the selection.
- **Play:** Space plays and pauses; ← and → step one frame.
- ⌘Z undoes and ⇧⌘Z redoes.

Then:

- **Save** (⌘S) replaces the recording with the trimmed version, without re-encoding where possible, and copies it.
- **Copy** (⌘C) copies the recording with your trim and cuts.
- **Export** writes a new file next to the recording, with these options, and copies it:
  - **MP4** or **GIF**
  - for a GIF, 10, 15 or 24 fps, and 480, 720 or 1080 px wide or the recording's own width (never wider than the recording). A GIF keeps the first 60 seconds.
  - for an MP4, **Mute** to leave the sound out
  - 1×, 1.5× or 2× speed

The estimated size of the exported file is shown before you export. Closing the window with unsaved trims or cuts asks whether to save them.

## Keyboard shortcuts

### Global

Every capture and recording action can have a global shortcut, and a [`shot://` URL](#url-scheme). Shot takes over the macOS screenshot keys and turns off the matching macOS shortcuts while it runs, so a keyboard's screenshot key opens Shot too. When Shot quits, macOS gets its keys back.

| Shortcut | Action |
|---|---|
| ⌘⇧3 | Capture fullscreen |
| ⌘⇧4 | Capture an area. Press Space to pick a window instead. |
| ⌘⇧5 | Record an area. Press Space to pick a window, or Enter for the full screen. |

While you set up a recording, the record shortcut starts it. While you record, it stops the recording. You can change any shortcut in **Settings › Shortcuts**: click a shortcut, then press the new keys. Esc cancels and Delete clears it.

To keep the macOS screenshot tool, turn off **Use Shot for ⌘⇧3 to ⌘⇧5** in **Settings › Shortcuts**. macOS gets its keys back, and Shot uses the same keys with ⌃ in place of ⌘: ⌃⇧3, ⌃⇧4, ⌃⇧5, plus ⌃⇧W for a window.

Record Fullscreen and Record Window have no shortcut until you set one. Capture Window has none while Shot uses ⌘⇧3 to ⌘⇧5; press Space after ⌘⇧4 instead.

### While selecting

| Key | Action |
|---|---|
| Space | Switch between picking an area and picking a window. While dragging, hold it to move the area. |
| Return | Record the full screen (recording only) |
| Esc | Cancel |

### Recording setup

| Key | Action |
|---|---|
| Return | Start recording after a 3-second countdown |
| Esc | Cancel |

### Annotation editor

| Key | Action |
|---|---|
| V A L R O D T S H F P B N C | Choose a tool (see [Tools](#tools)) |
| Delete | Delete the selection |
| Esc | Deselect |
| Arrow keys | Nudge the selection 1 pixel (10 with Shift) |
| ⌘C | Copy the selection, or the whole image when nothing is selected |
| ⌘V | Paste an annotation or an image |
| ⌘D | Duplicate the selection |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘+ / ⌘- | Zoom in / out |
| ⌘0 | Zoom to fit |
| ⌘1 | Actual size |
| Space-drag | Move around when zoomed in |
| ⌘S | Save and copy |

### Video editor

| Key | Action |
|---|---|
| Space | Play or pause |
| ← / → | Step back or forward one frame |
| Shift-drag | Select a section of the timeline |
| Delete | Cut the selected section |
| Esc | Clear the selection |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘C | Copy the edited video |
| ⌘S | Save and copy |

### Gallery

| Keys | Action |
|---|---|
| Arrow keys, Home, End | Move the selection (⇧ extends it) |
| Return | Edit the selection |
| Space | Quick Look |
| ⌘A, ⌘⇧A | Select all, deselect all |
| ⌘C | Copy |
| ⌘R | Show in Finder |
| Delete or ⌘Delete | Move to the Trash |
| ⌘F | Search |
| ⌘+, ⌘− | Thumbnail size |
| Esc | Clear the selection |

### Any Shot window

| Key | Action |
|---|---|
| ⌘W | Close the window |
| ⌘, | Open Settings |
| ⌘Q | Quit Shot |

## URL scheme

Use `open "shot://…"` to run Shot from a launcher, the Shortcuts app, or a script:

| URL | Action |
|---|---|
| `shot://capture-area`, `capture-fullscreen`, `capture-window` | Take a screenshot |
| `shot://record`, `record-fullscreen`, `record-window` | Set up, confirm, or stop a recording |
| `shot://pause` | Pause or resume the recording |
| `shot://annotate?path=<file>` | Open an image in the editor, or a video in the video editor |
| `shot://edit-video?path=<file>` | Open a video in the video editor to trim it |
| `shot://gallery` | Open the gallery |
| `shot://settings?section=<name>` | Open Settings at `general`, `capture`, `quickAccess`, `recording`, `shortcuts`, or `about` |

`path` can start with `~`. URL-encode spaces and other special characters, for example `open "shot://annotate?path=~/Desktop/My%20Shot.png"`. The older `shot://record?full=1` still works and does the same as `shot://record-fullscreen`.

## Settings

Open Settings from the menu bar icon, or with ⌘, while a Shot window is in front.

| Section | What you can change |
|---|---|
| General | Launch at login, the capture sound, hiding Shot's own windows from captures, cropping the menu bar off full-screen captures, the save folder, the file name, PNG or JPEG, and scaling Retina captures to 1× |
| Capture | What happens after a capture (save, copy, Quick Access, or the editor), the magnifier, the crosshair, the cursor, and window shadows |
| Quick Access | The screen corner and how long cards stay |
| Recording | Frame rate, cursor, region outline, copying to the clipboard, microphone, system audio, and the camera bubble |
| Shortcuts | The macOS screenshot keys and every global shortcut |
| About | Updates, permissions, the capture folder, and resetting all settings |

## Updates

Shot updates itself through [Sparkle](https://sparkle-project.org) once you allow it to check for updates. The second time you open Shot, it asks whether to check automatically. If you say yes, it fetches the update feed from GitHub once a day, and asks before installing a new version unless you tell it to install updates automatically. You can change this, or check by hand, in **Settings › About** or with **Check for Updates…** in the menu bar menu.

Every release is signed with the same certificate, so macOS keeps Shot's Screen Recording access after an update. If you installed Shot before it could update itself, macOS asks for that access once more after your next install.

## Privacy

Shot collects no analytics, and the only time it connects to the network is to check for updates, after you agree to it (see [Updates](#updates)). The GitHub links in Settings › About open in your browser.

Captures go to the folder you choose in Settings (`~/Pictures/Shot` by default) or stay in a temporary folder when saving is off.

Shot needs Screen & System Audio Recording access for every capture. It asks for Microphone and Camera access only when you first record with them.

## Removing Shot

Quit Shot and move it to the Trash. Quitting gives the screenshot keys back to macOS. If ⌘⇧3 to ⌘⇧5 still do nothing, for example because Shot crashed before you removed it, turn the shortcuts back on in **System Settings › Keyboard › Keyboard Shortcuts › Screenshots**.
