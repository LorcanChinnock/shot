# Image editor

Read this before changing annotations, their rendering or the editor's undo.

- `EditorDocument` / `Annotation` (ShotCore) is the model.
- `AnnotationRenderer` is shared by the on-screen canvas, flattened export, and the video compositors (`ProjectCompositor` via `AnnotationFrame`/`RenderCache`), so a rendering change affects them all.
- Undo is snapshot-based through ShotCore's generic `UndoStack`, not `NSUndoManager`. Group continuous edits (slider drags, held keys) into one step. View state like zoom is not undoable.
- Annotation outlines are `CGPath`s, hit-tested by Core Graphics. Filters are `CoreImageEffects`, text is `CoreTextShaper`, and OCR is Vision.
- `EditorModel` keeps view state and talks to the canvas. The undo steps, coalescing and unsaved-changes tracking are ShotCore's `EditHistory`, and what the crop tool applies is decided by `CropEditing`.
