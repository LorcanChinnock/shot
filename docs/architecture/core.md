# ShotCore

Read this before moving logic between ShotCore and the app, or changing how images and drawing are handled.

`Sources/ShotCore` holds everything that needs no window, display or permission: the undo stack, keyframes, cut list and trim range, hotkeys (`ShotAction`, `KeyCombo`), layout math and text wrapping (`TextLayout`, `NoteLayout`), the annotation model and renderer, the timeline and composition, GIF export, preferences, file naming and the gallery. It imports no AppKit, SwiftUI or Cocoa (`make lint` checks).

ShotCore calls Apple's frameworks directly, with no protocol in between:
- Images are `CGImage`s, so a capture keeps its own colour space. `ImageCodec` reads and writes them with ImageIO.
- Drawing takes a `CGContext`. `CGContext+Drawing.swift` adds the bitmap factory, the CTM-mapped `setShadow` and drawing of `CoreTextLine`s.
- Annotation outlines are `CGPath`s, hit-tested by Core Graphics. Filters are `CoreImageEffects`, text is `CoreTextShaper`, OCR is Vision.
- Video goes through `AVVideoReader`, `AVVideoAssembler` and `AVVideoWriter`.

If logic can be tested without a window, it goes in ShotCore with a test. The one test target is `Tests/ShotCoreTests`: mostly top-level `@Test func` with sentence-style names, plus the `PerfTests` budgets.
