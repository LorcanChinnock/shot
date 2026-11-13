# ShotCore

Read this before moving logic between ShotCore and the app, or changing how images and drawing are handled.

`Sources/ShotCore` holds everything that needs no window, display or permission: the undo stack, keyframes, cut list and trim range, hotkeys (`ShotAction`, `KeyCombo`), layout math, text wrapping and the sizes of parts of a text (`TextLayout`, `NoteLayout`, `TextRuns`), the annotation model and renderer, the timeline and composition, GIF export, preferences, file naming and the gallery. It imports no AppKit, SwiftUI or Cocoa (`make lint` checks).

The redesign's placement and sizing rules live here too, so they're tested without a window. Examples are where the capture bar and its labels sit (`CaptureBarLayout`, `OverlayBarPlacement`), where the style bar goes (`StyleBarPlacement`), what each editor panel shows (`StylePanelLayout`, `VideoInspectorPanel`) and each `Moment`'s length. The app's view then draws what ShotCore decided.

ShotCore calls Apple's frameworks directly, with no protocol in between:
- Images are `CGImage`s, so a capture keeps its own colour space. `ImageCodec` reads and writes them with ImageIO.
- Drawing takes a `CGContext`. `CGContext+Drawing.swift` adds the bitmap factory, the CTM-mapped `setShadow` and drawing of `CoreTextLine`s.
- Annotation outlines are `CGPath`s, hit-tested by Core Graphics. Filters are `CoreImageEffects`, text is `CoreTextShaper`, OCR is Vision.
- Video goes through `AVVideoReader`, `AVVideoAssembler` and `AVVideoWriter`.

If logic can be tested without a window, it goes in ShotCore with a test. The one test target is `Tests/ShotCoreTests`, mostly top-level `@Test func`s with sentence-style names. Launch time, memory and idle CPU are measured on the built app by `make perf-app`, not in the tests.
