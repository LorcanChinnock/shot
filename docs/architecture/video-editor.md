# Video editor and GIF export

Read this before changing the timeline, trim, cuts, keyframes or GIF export.

- `VideoEditorModel` keeps its undo steps in ShotCore's `VideoEditHistory`, which also decides which changes join the step before them. What crop mode shows and applies, what stays selected after an undo and how a cut selection is marked are `Project` and `TimelineSelection` extensions in `VideoEditing+Selection.swift`.
- The timeline and composition logic is in ShotCore (`Timeline*`, `ProjectComposition`). So are keyframes, trim and cuts (`Keyframes`, `TrimRange`, `VideoCuts`).
- GIF export reads frames (`GIFExporter`, `GIFStreamWriter`) and encodes them (`GIFEncoder`, `ColorQuantizer`).
- Video goes through `AVVideoReader`, `AVVideoAssembler` and `AVVideoWriter`.
- The title bar (`VideoEditorTitleBar` in `VideoEditorView.swift`) follows the image editor's: the file and what's changed, read from ShotCore's `VideoEditSummary`, then Undo, More tools, Draw (`toggleDrawing()`), Save or Save Copy, and Export as the one main button, which steps back to secondary in crop mode. Draw no longer opens the tracks.
- While Draw is on, `DrawToolColumn` (in `AnnotationPalette.swift`) floats over the left of the video with the tools ShotCore's `VideoDrawTools` lists, and `AnnotationPalette`, now one row of colour, fill, width and tool options, sits under the video. `tracksExtraHeight` counts that row whether or not the tracks show, so `fitWindowToTracks` grows the window for it. Crop video, or C while drawing, calls `cropFromDrawTools()`, which keeps the column up (`showsDrawTools`) and picks the tool again through `toolAfterCrop` when the crop is applied, cancelled or undone.
- Annotations on a video are drawn by the shared renderer; see [image-editor.md](image-editor.md).
