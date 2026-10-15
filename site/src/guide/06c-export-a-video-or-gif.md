---
title: Export a video or GIF
summary: "Export an MP4 or a GIF at the size, frame rate and speed you want, and reopen the edit later."
group: Edit and share
---

![The video editor with a trimmed start, a cut where the recording went to another page, a Best day label and an arrow over the video, and the GIF export options](../../../docs/media/video-editor.png)

## Export

In the video editor, **Export** writes a new file next to the recording and copies it. Choose:

- **MP4** or **GIF**.
- **Speed:** 1×, 1.5× or 2×. For an MP4, speed is available only while the edit is trims and cuts, when Save reads **Save**, not **Save Copy**.
- **For a GIF:** 10, 15 or 24 frames per second, and 480, 720 or 1080 pixels wide, or the recording's own width (**Full**). It's never wider than the recording.
- **For an MP4:** **Mute** to leave the sound out.

The estimated file size shows before you export. **Cancel**, or <kbd>Esc</kbd>, stops an export that's under way.

> [!NOTE]
> A GIF keeps the first 60 seconds of what plays, so 120 seconds of video at 2×. An MP4 that's re-encoded is H.264, or HEVC when H.264 would drop frames: a 120 fps recording, or one above 30 fps that's larger than 2560 × 1600, such as a full Retina screen.

> [!TIP]
> For a quick GIF without opening the editor, click **Export GIF** on the recording's [Quick Access](#quick-access) card. It uses the frame rate and width you last chose here.

## Reopen an edit later

**Save Copy** and **Export** keep your edit as a project: every lane, clip, annotation, keyframe and style. Open the copy or the export later, from the gallery, Quick Access or a `shot://edit-video` link, and it opens as the recording with the edit still live, so you can change it and save again.

A GIF works the same way: **Edit** on it in the gallery, or a `shot://annotate` link, opens its project in the video editor.

- The project follows the recording when you move or rename it. If the recording is gone, or **Save** has since trimmed it, the copy opens as itself.
- An imported file that has moved is found again if it was beside the recording, or in a folder inside the recording's folder, and moved with it. One that can't be found is left out, with a message naming it, and the rest of the edit opens.
- **Save** on an edit that's only trims and cuts replaces the recording itself, so there's no project to keep.
- To edit a copy or export as itself instead, choose **Edit › Flatten**, or open the recording. A flattened GIF opens in the annotation editor.

Shot keeps projects in its own Application Support folder, not in your files, so a video you share never carries them.

> [!NOTE]
> **When an agent edits a recording:** a trim from `shot trim` or `trim_video` saves like **Save Copy**. It never replaces the recording, and the new file opens in the video editor with the rest of the recording there to drag back. `shot gif` and `make_gif` save like **Export**, so **Edit** on the GIF opens the trim too.
