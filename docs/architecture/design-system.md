# Design system and views

Read this before changing shared UI components, window chrome or a view in a lazy collection.

- The design system is in `Sources/Shot/Design`. `Brutal` holds the tokens in `BrutalStyle.swift`, and `GlassWindow.swift` the window chrome, the see-through `SidebarMaterial` and the dark floating panels.
- A floating panel (a toast, the capture bar, recording controls, a countdown) is a `FloatingPanelWindow` sized to its shape, with `.floatingPanel(shape)` on its content and `floating: true` on its buttons. It uses the system window shadow, not a drawn one, because a drawn shadow needs a transparent margin that catches clicks.
- Motion comes from `Motion` in `Design/Motion.swift`, which turns each ShotCore `Moment` (its length, and what Reduce Motion plays instead) into a SwiftUI animation. Don't write a duration or spring by hand. A moment plays only after its work is done, so start it after the copy or save, never before.
- A moment drawn over a whole screen, like `ViewfinderSnap`, uses Core Animation shape layers, not a SwiftUI view. A transparent screen-sized SwiftUI view paints a screen-sized bitmap, and that cost 6 MB in `make perf-app`.
- Views in lazy collections (`LazyVGrid`, `List`, `LazyVStack`): a row or tile reads only its own state. It takes plain values, not the shared `@Observable` model, for anything that changes often (selection, hover, the playing item), and is `Equatable` with `.equatable()`, so one change re-evaluates the few views whose values changed, not all of them.
- Put footers and status text that read such state in their own `View` structs, not computed properties of a big body.
- One interaction must cost the same however big the library is.
- Use a single `onTapGesture` and read `NSApp.currentEvent?.clickCount`. `onTapGesture(count: 2)` delays every single click (lint rejects it).
- UI and model types are `@MainActor`. Heavy work runs in `Task.detached`, and CG types cross actors through `@unchecked Sendable` wrappers (`SendableImage`, `EditorDocument`).
