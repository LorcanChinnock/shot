# Video editor

![The video editor timeline with a text label and an arrow on their own lanes, the arrow's Pop keyframes, a trimmed start, a cut, the Inspector and the GIF export options](../../../docs/media/video-timeline.png)

Open a recording from its Quick Access card (the scissors button, **Edit Video**), from the [gallery](#gallery), or with [`shot://edit-video`](#url-scheme).

- **Play:** Space plays and pauses; ← and → step one frame, ⇧← and ⇧→ one second, and Home and End go to the start and end. Click the ruler to move the playhead.
- **Trim:** drag the yellow handles at either end of the main track. What you trim off stays greyed out.
- **Cut:** Shift-drag on the timeline to select a section, then press Delete to cut it out.
- **Split:** **Split** (S) splits the clips under the playhead, and **Delete** (⌫) cuts out the selected clip and closes the gap. **Snap** (N) snaps the playhead, and clips you drag or trim, to clip edges and the playhead. **Tracks** (T) shows or hides the tracks; once the edit is more than trims and cuts, they stay shown.
- **Zoom:** pinch, or ⌘+ and ⌘−, to zoom the timeline, and **Fit** or ⌘0 to fit it to the window.
- **Import:** in the **Import** menu, **Add Video or Audio at Playhead…** puts a file's picture on a new lane above the main track and its sound on a lane of its own, or drop the file on the window. **Add Video to End…** adds a video to the end of the main track. Drag a clip on another lane to move it in time, or drag its edges to trim it. Sound lanes show the sound's waveform, which grows and shrinks with the clip's volume.
- **Annotate:** click **Annotate** to draw arrows, shapes, text, blur and more over the video, with the annotation editor's tools except crop and hand; to crop the video, see **Crop** below. To add a picture, use the image button in the same toolbar. Each annotation starts at the playhead and shows for 3 seconds, on the first annotation lane that's free at that time and not locked, or else on a new lane.
- **Move, scale and rotate:** select a clip, the recording included, while the playhead is on it, and a yellow box appears over the video. Drag inside it to move the clip, drag a corner to scale it about its centre, and drag the pink knob above it to rotate it.
- **Crop:** with nothing selected, press C, or click **Crop** under **Frame** in the Inspector, to crop the video's frame. Select a clip, the recording included, and press C, double-click its yellow box, or click **Crop** in the Inspector, to crop that clip's picture.
  - Crop mode works as in the [annotation editor](#cropping): what's cropped off shows dimmed, drag a handle to resize the crop or inside it to move it, hold Shift to keep its shape, and pick an **Aspect** (Free, 1:1, 4:3 or 16:9). **Reset** shows everything again. Return or **Apply** applies the crop as one undo step, and Esc or **Cancel** leaves it as it was.
  - A frame crop changes the size of the video, so cropping off the menu bar of a 1920 × 1080 recording gives a smaller video, not a scaled-up one. Sizes are rounded down to even numbers. MP4 and GIF exports both come out at the cropped size, and nothing moves in the picture. The Inspector shows the size under **Frame**, with **Reset** to take the crop off.
  - A cropped clip still moves, scales and turns as a whole, about the middle of its whole picture, and its corners, shadow and border follow the cropped edge. **Reset Crop** in the Inspector shows all of it again.
  - Neither crop is keyframed. For a zoom over time, key the clip's scale and position.
- **Inspector:** click **Inspector** to see the selected clip's or annotation's properties:
  - Position, scale, rotation (**Turn**) and opacity.
  - The volume of a clip on a sound lane, from 0 to 200%.
  - **Drawn**, how much of an arrow, line or pen stroke is drawn.
- **Keyframes:** the diamond beside each property in the Inspector keys it at the playhead, or takes that keyframe away. Once a property has keyframes, changing it at another time keys it there. K keys everything the selected clip or annotation can animate at the playhead, or takes those keyframes away.
  - Keyframes show as diamonds on the lane. Click one to go to it and choose its **Easing** (Linear, Ease in, Ease out, Ease in-out or Spring), drag it to move it, or press Delete to take it away.
  - **Fade In**, **Fade Out**, **Pop**, **Slide In** and **Draw On** add ready-made keyframes at the start or end, and **Clear Keyframes** removes them all.
- **Layers:** the annotation and picture lanes above the main track are the layers, topmost first. A blur, pixelate or spotlight affects the lanes under it, video included, not those over it.
  - Drag an annotation or an imported clip up or down to put it on another lane. Drop it between lanes, or on a lane that's locked, taken at that time or holds the other kind, and it gets a new lane of its own.
  - ⌘] and ⌘[ move the selected annotation or clip a lane up or down, and ⌥⌘] and ⌥⌘[ to the top or bottom.
  - Double-click an annotation's label, or right-click it and choose **Rename**, to name it as in the [annotation editor's Layers](#layers). Return or clicking elsewhere keeps the name, Esc cancels, and an empty name goes back to the automatic one. The name is kept with the [project](#video-editor) when you save, and it's never drawn in the video.
  - Right-click a lane to lock it (Split and new annotations then leave it alone), hide it, mute a sound lane, or delete an annotation lane. The same buttons show at the lane's left edge when you point at it.
- **Style:** select a clip or an annotation and click **Style** in the **Inspector** for the same shadows, borders and corners as the [annotation editor's Style](#style).
  - A clip can have rounded corners, a shadow, and a Hairline or Solid border. The recording itself can too, which makes the video drawn rather than only trimmed.
  - The corners, shadow and border grow and shrink with the clip's scale, and Pop and Slide In lift the shadow briefly as the clip comes in.
  - On a clip, Glow takes the colour of the frame's edge, and a Hairline is light on a dark frame and dark on a light one, as on an image. The edge is read once a second.
  - Pointing at a preset, or moving to it with the arrow keys, previews it on the annotation or clip. A recording you've only trimmed shows a clip's new style a moment after you click instead.
  - Each click is one undo step, and so is each slider drag. **Edit › Copy Style** (⌥⌘C) and **Paste Style** (⌥⌘V) work here as in the annotation editor, and an annotation you style is remembered for the next one of its kind, as there.
- **Delete** takes away, in this order, the selected keyframe, the selected section, or the selected clip or annotation. **Esc** cancels an export, then clears the selected section, then deselects, then stops annotating.
- ⌘Z undoes and ⇧⌘Z redoes.

Then:

- **Save** (⌘S) replaces the recording with the trimmed version, without re-encoding where possible, and copies it. Once the edit is more than trims and cuts, the button reads **Save Copy** and writes a new file next to the recording instead. An import, annotation or keyframe, a crop, a moved or styled recording, a changed volume, reordered clips, or a hidden or muted track each switches it to **Save Copy**. The title shows **TRIMMED** while you've only trimmed the ends, and **EDITED** once there's a cut or more.
- **Copy** (⌘C) copies the edited video, everything included.
- **Export** writes a new file next to the recording, with these options, and copies it:
  - **MP4** or **GIF**
  - for a GIF, 10, 15 or 24 fps, and 480, 720 or 1080 px wide or the recording's own width (**Full**; never wider than the recording). A GIF keeps the first 60 seconds of what plays, so 120 seconds of video at 2×.
  - for an MP4, **Mute** to leave the sound out. An MP4 that's re-encoded is H.264, or HEVC when H.264 would drop frames: a 120 fps recording, or one above 30 fps that is larger than 2560 × 1600, such as a full Retina screen.
  - 1×, 1.5× or 2× speed. Speed is unavailable for an MP4 whenever Save reads **Save Copy**.

The estimated size of the exported file is shown before you export. **Cancel**, or Esc, stops an export under way. Closing the window asks whether to save, or to save a copy, when you've changed anything since you last saved, saved a copy or exported.

Save Copy and Export keep the edit as a project: every lane, clip, annotation, keyframe and style. Open the copy or the export later, from the gallery, Quick Access or a `shot://edit-video` link, and it opens as the recording with the edit still live, so you can change it and save again. A GIF works the same way: **Edit** on it in the gallery, or a `shot://annotate` link, opens its project in the video editor. Shot keeps projects in its own Application Support folder, not in the files, so a video you share never carries them.

- The project follows the recording when you move or rename it. If the recording is gone, or Save has since trimmed it, the copy opens as itself.
- An imported file that has moved is found again if it was beside the recording, or in a folder inside the recording's folder, and moved with it. One that can't be found is left out, with a message naming it, and the rest of the edit opens.
- **Save** on an edit that's only trims and cuts replaces the recording itself, so nothing is kept over it.
- To edit a copy or export as itself instead, choose **Edit › Flatten**, or open the recording. A flattened GIF opens in the annotation editor.
- An agent's trim, from `shot trim` or `trim_video`, saves like **Save Copy**: it never replaces the recording, and the new file opens in the video editor with the rest of the recording there to drag back. `shot gif` and `make_gif` save like **Export**, so **Edit** on the GIF opens the trim too.
