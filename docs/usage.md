# Using Shot

The full guide to Shot. For a quick introduction, see the [overview](../README.md).

- [Screenshots](#screenshots)
- [Quick Access](#quick-access)
- [Screen recording](#screen-recording)
- [Annotation editor](#annotation-editor)
- [Video editor](#video-editor)
- [Gallery](#gallery)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [URL scheme](#url-scheme)
- [Settings](#settings)
- [Updates](#updates)
- [Privacy](#privacy)
- [Removing Shot](#removing-shot)

## Screenshots

Shot lives in the menu bar. Its menu lists every capture and recording action with its shortcut, **Open Gallery** and **Open Capture Folder**, and while you record, **Pause Recording** and **Stop Recording**.

- **Area (⌘⇧4):** the screen freezes, and you drag out an area. A magnifier next to the pointer helps you find exact edges. Hold Shift for a square, or press Tab to step through 1:1, 4:3, 3:2, 16:9 and back to free (Shift-Tab steps back); the direction you start dragging picks landscape or portrait, and X rotates it mid-drag. Hold Space while dragging to move the area. A label by the pointer shows the size in pixels, and the ratio when one is set. Press Esc to cancel.
- **Window:** press Space after ⌘⇧4, then click a window. Shot keeps the macOS window shadow unless you turn it off in Settings › Capture.
- **Fullscreen (⌘⇧3):** captures the screen under the pointer.

After a capture, Shot saves it, copies it, and shows it in [Quick Access](#quick-access). Choose which of these happen, or open the editor straight away, in **Settings › Capture**. Clipboard copies are always PNG.

## Quick Access

![The Quick Access card, hovered, with Close, Annotate, Copy, Save As… and Show in Finder](media/quick-access.png)

A floating card appears in a bottom corner of the screen under the pointer after each capture. Hover it to show its buttons:

- **Copy** or **Save As…**
- **Annotate** a screenshot, or **Edit** a recording in the [video editor](#video-editor)
- **Export GIF** from a recording. This uses the GIF frame rate and width you last chose in the video editor, and keeps the first 60 seconds.
- **Show in Finder**, or **Close** the card
- Drag the card into another app, or onto an open editor to [combine images](#combine-images)

New cards stack above older ones, up to five; a sixth closes the oldest. Cards close on their own after 8 seconds, and hovering a card pauses the timer. In **Settings › Quick Access**, pick the bottom-left or bottom-right corner, and 4, 8, 15 or 30 seconds, or **Never**.

## Screen recording

![The recording controls: elapsed time, Pause, the camera bubble, discard and Stop](media/recording-controls.png)

Press ⌘⇧5, then drag out an area (the magnifier helps here too), press Space and click a window, or press Enter for the full screen. Recording starts as soon as you let go, with the camera bubble, microphone and cursor set as in **Settings › Recording**. Record Fullscreen and Record Window start on their own shortcuts, once you set them.

To adjust first, hold ⌥ as you finish the selection, or turn on **Adjust before recording** in **Settings › Recording** to do it every time. You can then adjust the frame, switch between area, screen and window, and turn the camera bubble, microphone and cursor on or off for this recording. Press Return or click **Record** to start, or Esc to cancel. **Countdown** in the same settings adds a 3 or 5 second countdown before recording starts, with or without this step. Esc during the countdown goes back to the adjust step if it was shown, and otherwise cancels the recording.

If you picked the area with a ratio (Tab or Shift), the frame's handles keep it.

A window recording captures just that window: it follows the window when it moves and leaves out anything on top of it. It has no camera bubble, and dragging the frame turns it into an area recording.

While recording, the controls let you pause and resume, stop and save, and discard the recording; for 5 seconds after a discard, **Undo** brings it back. With the microphone on, they also show its level and a button to mute it, which silences only the microphone. With the camera bubble on, they show, hide or resize it. The menu bar menu has **Pause Recording** and **Stop Recording** too. On a Mac with a notch, when there's no room for the controls outside the recorded area, they move into the notch: a black pill shows the elapsed time, and hovering it shows the controls. Pressing any record shortcut again, or opening `shot://record`, stops the recording.

Recordings are H.264 MP4 at 30 or 60 fps, written to your save folder as they record. With a display that refreshes at 120 Hz or faster, such as a ProMotion MacBook Pro, **Settings › Recording** also offers 120 fps, which records, and exports from the video editor, as HEVC MP4; on a slower screen that recording drops to 60 fps. When a recording finishes, Shot copies the file to the clipboard unless you turn off **Copy to clipboard** in **Settings › Recording**, and shows it in [Quick Access](#quick-access) unless you turn that off in **Settings › Capture**. A recording never opens in the video editor by itself. In **Settings › Recording** you can also show the cursor, outline the recorded area with **Region border** (the outline never appears in the video), and record your microphone and system audio. System audio is sound from other apps; Shot's own sounds are left out.

### Camera bubble

A round webcam overlay that is recorded with your screen. It starts in the bottom-left corner of the recorded area, and stays inside it. Drag it to move it, and double-click it to step through small, medium and large; the size you pick becomes the default. Pick the camera and the size in **Settings › Recording**. A window recording has no camera bubble, and an area too small for the bubble records without it.

macOS asks for Microphone and Camera access the first time Shot uses them.

## Annotation editor

![The editor toolbar: the tools, then the colours and line widths for the arrow tool](media/editor-toolbar.png)

Open the editor from a Quick Access card, by turning on **Open in editor** in Settings › Capture, or with [`shot://annotate`](#url-scheme).

### Tools

Press a tool's key when you aren't typing text.

| Key | Tool |
|---|---|
| V | Select: move, resize and restyle what you've drawn |
| H | Hand: drag to move around when zoomed in, without touching annotations |
| A | Arrow |
| L | Line |
| R | Shape: rectangle, rounded rectangle, ellipse, triangle, diamond or star |
| D | Pen: freehand |
| T | Text |
| S | Sticky note |
| M | Highlight: a freehand marker |
| F | Spotlight: dims or blurs everything outside the area |
| B | Redact: blurs or pixelates the area |
| N | Counter: numbered circles |
| C | Crop |

Hover a tool to see what it does. While you draw, Shift keeps a box square, keeps an arrow, line or highlight at 45° steps, and Option draws from the centre; Esc cancels what you're drawing. Tools that draw a mark show a colour and one of three line widths below the tools; for text, sticky notes and counters the widths are text sizes, and changing the size or colour while you type updates the text as you go. Text and sticky notes also offer left, centre or right alignment for their lines. The shape tool also offers the shape and a fill. Redact offers blur or pixelate, and an amount slider for how far the blur spreads or how big the blocks are. Spotlight offers its shape (rectangle, rounded rectangle or ellipse), a soft edge that fades it into the dim, whether to darken or blur outside it, and how strongly; the effect and strength apply to every spotlight in the image, since they share one dim. The highlight and sticky notes keep their own colours, yellow at first, so they don't take the colour of your arrows. The last swatch picks any colour, and each palette remembers the last one you picked. The editor remembers the colour, width and options you used, and the last drawing tool: a new window starts with it, or with the arrow.

### Editing annotations

- Click an annotation with the select tool to select it, then drag it, or drag its handles to resize it. Text and counters have no handles, and a placed image has handles at its corners only. Drag the middle handle of a line or arrow to bend it. Drag one of the round handles inside a rounded rectangle's corners to set how round all four are, up to a pill; they hide on a box too small to grab them. Choosing a colour, width or option restyles the selection.
- What you've just drawn stays selected until you draw the next thing, click elsewhere or press Esc, so you can fix its shape, colour, width or fill from the toolbar, or drag its handles, without switching to the select tool. The change also applies to what you draw next.
- Double-click text or a sticky note to edit it. Clicking a note with the note tool edits it too.
- Press Delete to remove the selection, and Esc to deselect. While you type in a text box or sticky note, Esc finishes it; ⌘Z removes it again.
- Arrow keys nudge the selected annotation by 1 pixel, or 10 with Shift.
- ⌘C copies the selected annotation, ⌘V pastes it, and ⌘D duplicates it. You can paste into another editor window. With nothing or several things selected, ⌘C copies the whole image.
- ⌘Z undoes and ⇧⌘Z redoes.

### Layers

Click **Layers** (⌘L) to list the annotations, frontmost first, with the image locked at the bottom. Click a row to select it on the canvas, ⌘-click or ⇧-click to select several, drag a row by its handle to reorder (Escape or dropping outside the list cancels), and press Delete or click the bin to delete. The eye hides a layer, which also leaves it out of Copy and Save, and the lock stops it being picked, moved or deleted. Right-click a row to duplicate, delete, lock or hide. ⌘] and ⌘[ move the selection forward and back, and ⌥⌘] and ⌥⌘[ bring it to the front or send it to the back.

Each layer acts on everything under it and nothing over it: a blur, pixelate or spotlight covers the layers below it, and layers above it are drawn over it. All spotlights share one dim, at the lowest spotlight's place in the list.

### Canvas

Annotations can reach past the edges of the screenshot: the canvas grows to fit them, except for spotlights. The **Canvas** menu fits the canvas to its content, trims it back to the image, and sets the background of the extra space to transparent (PNG only), white, or one of the palette colours. It starts transparent for a PNG and white for a JPEG.

### Style

Click **Style** in the toolbar to round the corners of your screenshot and give it a shadow or a border. With something selected, Style acts on that instead: a placed image gets the same choices, and a shape, arrow, line, pen stroke, counter or text gets a shadow or glow, and text an outline too. It's greyed out for blurs, pixelates, spotlights, the highlight and notes, which already have a shadow of their own, and when several things or a locked one are selected. Nothing is styled until you ask. Each preset shows your screenshot, image, shape or text with that preset on it.

- **Shadow:** None, Soft, Float, Contact or Glow. Point at one to preview it on the canvas, and click to apply it. The arrow keys move between the presets, previewing each, and Return applies the one they're on. A window captured with the macOS shadow already has one, so Style shows **Uses macOS window shadow** in place of its choices: its image includes the shadow's see-through margin, which a second shadow, a border or corners would go round. Pasted styles and Use this style for new captures leave it as it is. Once there's a shadow, **Elevation** and **Opacity** sliders tune it into a custom one. The light comes from above, so shadows fall below. On a coloured background the shadow takes a dark shade of it; on a transparent one it's black, and it's saved in the PNG so it looks right pasted anywhere. Glow takes the colour of the image's edge, or of the shape, arrow or text.
- **Border:** **Hairline** draws a one-pixel rim, light on dark content and dark on light, so a screenshot keeps its edge on a page of the same colour. **Solid** draws a line of one colour just outside the edge, following the rounded corners. **Outline** shows only for a screenshot or image with see-through pixels, such as a logo or a cut-out: it traces the image's shape, like a sticker. On text, Outline strokes round each letter, so it reads on a busy screenshot. Solid and Outline offer three widths, **S**, **M** and **L**, and the palette colours. They start at M, in the colour of the border already there, or else white, or on text black or white to stand out from its colour.
- **Corners:** the slider rounds the corners of the screenshot or an image.

A shadow or border on the screenshot grows the canvas just enough to fit it, and removing it shrinks the canvas back. Each click is one undo step, and so is each slider drag.

The style you give an image, a shape or arrow, or text is remembered: the next one you draw or add of that kind starts with it, even in a new editor window, until you pick None. The screenshot starts plain unless you turn on **Use this style for new captures**, at the bottom of Style when nothing is selected. New captures then open in the editor with the screenshot's current style. They're copied with it too: the plain capture is copied straight away, and the styled one replaces it a moment later, unless you've copied something else since. Quick Access shows the styled capture a moment later too, and its Copy and dragging the card use it. The saved file stays plain, so you can still change the style. Turn the switch off to stop, or style a screenshot differently and turn it on again to save the new style.

To reuse a style, select something and choose **Edit › Copy Style** (⌥⌘C), then select something else and choose **Paste Style** (⌥⌘V); with nothing selected, they copy from and paste on the screenshot. A style copied here pastes in the video editor too, and the other way round. Each thing takes only what it can have: a shape keeps its own corners, and text takes only an outline as its border. Copy Style needs one thing selected; Paste Style pastes on everything selected. **Edit › Apply Style to All Images** pastes it on the screenshot and every image you placed. Pasting is one undo step.

### Combine images

Click **Add an image** (⇧⌘I) to pick one of your recent captures, or **Choose File…** for any image files. You can also drag an image file or a Quick Access card onto the canvas, or press ⌘V with an image on the clipboard, to place another image beside your screenshot. A picked image goes beside the canvas. A dropped image is centred where you drop it; a pasted one goes beside the canvas. Placed images keep their full resolution, keep their aspect ratio when you resize them, and can be moved, nudged, copied and deleted like any other annotation.

### Zoom

Pinch, or press ⌘+ and ⌘-, to zoom. ⌘0 fits the canvas to the window and ⌘1 shows it at actual size. When zoomed in, scroll, hold Space and drag, drag with the middle mouse button, or drag with the hand tool (H) to move around.

### Saving

**Copy** copies the annotated image. **Save** (⌘S) writes it beside the original as `name (2).png` (or `.jpg`), then `name (3).png` and so on, and copies it; the original is never changed. Unsaved changes show **EDITED** in the title bar, and closing the window asks whether to save them.

## Video editor

![The video editor timeline with an arrow on its own lane, a trimmed start, a cut, an audio track with its waveform, the Inspector and the GIF export options](media/video-timeline.png)

Open a recording from its Quick Access card (the scissors button, **Edit**), from the [gallery](#gallery), or with [`shot://edit-video`](#url-scheme).

- **Play:** Space plays and pauses; ← and → step one frame, ⇧← and ⇧→ one second, and Home and End go to the start and end. Click the ruler to move the playhead.
- **Trim:** drag the yellow handles at either end of the main track. What you trim off stays greyed out.
- **Cut:** Shift-drag on the timeline to select a section, then press Delete to cut it out.
- **Split:** **Split** (S) splits the clips under the playhead, and **Delete** (⌫) cuts out the selected clip and closes the gap. **Snap** (N) snaps the playhead, and clips you drag or trim, to clip edges and the playhead. T shows or hides the tracks.
- **Zoom:** pinch, or ⌘+ and ⌘−, to zoom the timeline, and **Fit** or ⌘0 to fit it to the window.
- **Import:** **Add Video or Audio at Playhead…** puts a file's picture on a new lane above the main track and its sound on a lane of its own, or drop the file on the window. **Add Video to End…** adds a video to the end of the main track. Drag a clip on another lane to move it in time, or drag its edges to trim it. Sound lanes show the sound's waveform, which grows and shrinks with the clip's volume.
- **Annotate:** draw arrows, shapes, text, blur and more over the video, with the annotation editor's tools except crop and hand. To add a picture, use the image button in the same toolbar. Each annotation starts at the playhead and shows for 3 seconds, on its own lane.
- **Move, scale and rotate:** select a clip, the recording included, while the playhead is on it, and a yellow box appears over the video. Drag inside it to move the clip, drag a corner to scale it about its centre, and drag the pink knob above it to rotate it.
- **Inspector:** the selected clip's or annotation's position, scale, rotation (**Turn**) and opacity, the volume of a clip on a sound lane, and **Drawn**, how much of an arrow, line or pen stroke is drawn. The diamond beside each one keys it at the playhead, or takes that keyframe away, and once a property has keyframes, changing it at another time keys it there. K keys everything at the playhead, or takes those keyframes away. Keyframes show as diamonds on the lane: click one to go to it and choose its **Easing** (Linear, Ease in, Ease out, Ease in-out or Spring), drag it to move it, or press Delete to take it away. **Fade in**, **Fade out**, **Pop**, **Slide in** and **Draw on** add ready-made keyframes at the start or end, and **Clear keyframes** removes them all.
- **Layers:** the annotation and picture lanes above the main track are the layers, topmost first. Drag an annotation or an imported clip up or down to put it on another lane; drop it between lanes, or on a lane that's taken at that time or holds the other kind, and it gets a new lane of its own. ⌘] and ⌘[ move the selected annotation or clip a lane up or down, and ⌥⌘] and ⌥⌘[ to the top or bottom. Right-click a lane to lock it (Split and new annotations then leave it alone), hide it, mute a sound lane, or delete an annotation lane; the same buttons show at the lane's left edge when you point at it. A blur, pixelate or spotlight affects the lanes under it, video included, not those over it.
- **Style:** select a clip or an annotation and click **Style** in the **Inspector** for the same shadows, borders and corners as the [annotation editor's Style](#style). A clip can have rounded corners, a shadow, and a Hairline or Solid border; the recording itself can too, which makes the video drawn rather than only trimmed. The corners, shadow and border grow and shrink with the clip's scale, and Pop and Slide in lift the shadow briefly as the clip comes in. On a clip, Glow takes the colour of the frame's edge, and a Hairline is light on a dark frame and dark on a light one, as on an image; the edge is read once a second. Pointing at a preset, or moving to it with the arrow keys, previews it on the annotation or clip; a recording you've only trimmed shows a clip's new style a moment after you click instead. Each click is one undo step, and so is each slider drag. **Edit › Copy Style** (⌥⌘C) and **Paste Style** (⌥⌘V) work here as in the annotation editor, and an annotation you style is remembered for the next one of its kind, as there.
- **Delete** takes away, in this order, the selected keyframe, the selected section, or the selected clip or annotation. **Esc** cancels an export, then clears the selected section, then deselects, then stops annotating.
- ⌘Z undoes and ⇧⌘Z redoes.

Then:

- **Save** (⌘S) replaces the recording with the trimmed version, without re-encoding where possible, and copies it. Once the edit is more than trims and cuts, with imports, annotations, keyframes, a moved or styled recording, or a hidden or muted track, the button reads **Save copy** and writes a new file next to the recording instead.
- **Copy** (⌘C) copies the edited video, everything included.
- **Export** writes a new file next to the recording, with these options, and copies it:
  - **MP4** or **GIF**
  - for a GIF, 10, 15 or 24 fps, and 480, 720 or 1080 px wide or the recording's own width (**Full**; never wider than the recording). A GIF keeps the first 60 seconds of what plays, so 120 seconds of video at 2×.
  - for an MP4, **Mute** to leave the sound out. An MP4 is H.264, or HEVC when H.264 would drop frames: a 120 fps recording, or one above 30 fps that is larger than 2560 × 1600, such as a full Retina screen
  - 1×, 1.5× or 2× speed. An MP4 with imports, annotations or transforms exports at 1×.

The estimated size of the exported file is shown before you export. **Cancel**, or Esc, stops an export under way. Closing the window with unsaved edits asks whether to save them, or to save a copy.

## Gallery

![The gallery: screenshots, a recording and a GIF, with filters, sort and the thumbnail size slider](media/gallery.png)

**Open Gallery** in the menu bar menu (or [`shot://gallery`](#url-scheme)) shows every screenshot, recording and GIF in your save folder, kept up to date as you capture. It's the first section of the same window as Settings. Captures taken with saving turned off aren't in it.

- **Filter** by All, Screenshots, Videos or GIFs, **search** by file name (⌘F), and **sort** by **Newest first**, **Oldest first**, **Name** or **Largest first**. Sorted by date, the gallery groups captures into Today, Yesterday, This Week, This Month and then each older month. The slider (or ⌘+ and ⌘−) sets the thumbnail size.
- **Select** with a click, ⌘-click, ⇧-click, ⌘A or the arrow keys, or tick the checkbox on a thumbnail to add it to the selection. **Select All** and **Deselect All** sit next to the count at the bottom.
- **Edit** (or Return) opens the selection, when none of it is a GIF, in the [annotation editor](#annotation-editor) or [video editor](#video-editor), and asks first if that's more than 8 items. Double-click a thumbnail, or use the pencil or scissors button on a hovered one, to open just that one.
- **Quick Look** with Space.
- The buttons at the bottom **Edit**, **Copy**, **Show in Finder** or **Move to Trash** the selection. Right-click for the same, plus **Quick Look**, **Export GIF** (a video) and **Rename…**. Trashed files go to the Trash; ⌘Z puts them back, and so can Finder.
- Drag a thumbnail into another app.

## Keyboard shortcuts

### Global

Every capture and recording action can have a global shortcut, and a [`shot://` URL](#url-scheme). Once it has Screen Recording access, Shot takes over the macOS screenshot keys and turns off the matching macOS shortcuts while it runs. When Shot quits, macOS gets its keys back. If you turn the macOS shortcuts back on in System Settings, Shot stops using those keys until you turn **Use Shot for ⌘⇧3 to ⌘⇧5** on again.

| Shortcut | Action |
|---|---|
| ⌘⇧3 | Capture fullscreen |
| ⌘⇧4 | Capture an area. Press Space to pick a window instead. |
| ⌘⇧5 | Record an area. Press Space to pick a window, or Enter for the full screen. |

While you set up a recording, the record shortcut starts it. While you record, it stops the recording. You can change any shortcut in **Settings › Shortcuts**: click a shortcut, then press the new keys, which must include ⌘, ⌥ or ⌃. Esc cancels and Delete clears it. Shot refuses a shortcut another action already has, and ⌘Q, ⌘W, ⌘Tab, ⌘Space, ⌘H and ⌘M. **Restore defaults** puts them all back.

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
| Return | Start recording, after the countdown if one is set |
| Esc | Cancel |

### Annotation editor

| Key | Action |
|---|---|
| V H A L R D T S M F B N C | Choose a tool (see [Tools](#tools)) |
| Shift / Option while drawing | Keep it square or at 45° / draw from the centre |
| Delete | Delete the selection |
| Esc | Deselect, or cancel what you're drawing |
| Arrow keys | Nudge the selection 1 pixel (10 with Shift) |
| ⌘C | Copy the selected annotation, or the whole image |
| ⌘V | Paste an annotation or an image |
| ⌘D | Duplicate the selection |
| ⌥⌘C / ⌥⌘V | Copy / paste a style |
| ⇧⌘I | Add an image: a recent capture or a file |
| ⌘L | Show or hide the layers |
| ⌘] / ⌘[ | Move the selection forward / back |
| ⌥⌘] / ⌥⌘[ | Bring the selection to the front / send it to the back |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘+ / ⌘- | Zoom in / out |
| ⌘0 | Zoom to fit |
| ⌘1 | Actual size |
| Space-drag or middle-drag | Move around when zoomed in |
| ⌘S | Save and copy |
| ⌘W | Close, asking to save changes |

### Video editor

| Key | Action |
|---|---|
| Space | Play or pause |
| ← / → | Step back or forward one frame |
| ⇧← / ⇧→ | Step back or forward one second |
| Home / End | Go to the start / end |
| Shift-drag | Select a section of the timeline |
| S | Split the clips under the playhead |
| K | Key everything at the playhead, or take those keyframes away |
| N | Turn snapping on or off |
| T | Show or hide the tracks |
| Delete | Take away the selected keyframe, section, or clip or annotation |
| Esc | Cancel an export, clear the selection, or stop annotating |
| ⌘] / ⌘[ | Move the selected annotation or clip a lane up / down |
| ⌥⌘] / ⌥⌘[ | Move the selected annotation or clip to the top / bottom lane |
| ⌘+ / ⌘− / ⌘0 | Zoom the timeline in / out / to fit |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘C | Copy the edited video |
| ⌥⌘C / ⌥⌘V | Copy / paste the selection's style |
| ⌘S | Save and copy |
| ⌘W | Close, asking to save changes |

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
| ⌘Z | Put back what you last moved to the Trash |
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
| `shot://settings?section=<name>` | Open Settings at `gallery`, `general`, `capture`, `quickAccess`, `recording`, `shortcuts`, or `about` |

`path` can start with `~`. URL-encode spaces and other special characters, for example `open "shot://annotate?path=~/Desktop/My%20Shot.png"`. The older `shot://record?full=1` still works and does the same as `shot://record-fullscreen`. An unknown action, or `annotate` or `edit-video` without a `path`, shows an error instead.

## Settings

Open Settings from the menu bar icon, or with ⌘, while a Shot window is in front.

| Section | What you can change |
|---|---|
| Gallery | The [gallery](#gallery) |
| General | Launch at login, the capture sound, hiding Shot's own windows from captures, cropping the menu bar off full-screen captures, the save folder, the file name, PNG or JPEG, and scaling Retina captures to 1× |
| Capture | What happens after a capture (save, copy, Quick Access, or the editor), the magnifier, the crosshair, the cursor, and window shadows |
| Quick Access | The screen corner and how long cards stay |
| Recording | Adjust before recording, the countdown, frame rate, cursor, region outline, copying to the clipboard, the microphone and its input (with a **Test**), system audio, and the camera bubble's camera (with a **Preview**) and size. It also sums up the GIF settings the video editor last used. |
| Shortcuts | The macOS screenshot keys and every global shortcut |
| About | The version, updates, permissions, the capture folder, links to the code, to report a bug and to sponsor Shot, and resetting all settings |

## Updates

Shot updates itself through [Sparkle](https://sparkle-project.org) once you allow it to check for updates. The second time you open Shot, Sparkle asks whether to check automatically. If you say yes, Shot asks GitHub once a day whether a new version is out, and installs it when you agree. Turn **Check for updates automatically** on or off, or **Check** by hand, in **Settings › About**, or use **Check for Updates…** in the menu bar menu. When a check finds a new version, that item becomes **Update to Shot** and the version.

Every release is signed with the same certificate, so macOS keeps Shot's Screen Recording access after an update. If you installed Shot before it could update itself, macOS asks for that access once more after your next install.

## Privacy

Shot collects no analytics, and the only time it connects to the network is to check for updates, after you agree to it (see [Updates](#updates)). The GitHub links in Settings › About, including Sponsor, open in your browser.

Captures go to the folder you choose in Settings (`~/Pictures/Shot` by default) or stay in a temporary folder when saving is off.

Shot needs Screen & System Audio Recording access for every capture. macOS asks for Microphone and Camera access only when Shot first uses them: when you record with them, or try them with **Test** or **Preview** in Settings › Recording.

## Removing Shot

Quit Shot and move it to the Trash. Quitting gives the screenshot keys back to macOS. If ⌘⇧3 to ⌘⇧5 still do nothing, for example because Shot crashed before you removed it, turn the shortcuts back on in **System Settings › Keyboard › Keyboard Shortcuts › Screenshots**.
