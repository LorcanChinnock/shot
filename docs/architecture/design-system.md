# Design system and views

Read this before changing shared UI components, window chrome or a view in a lazy collection.

- The design system is in `Sources/Shot/Design`. `Brutal` holds the tokens in `BrutalStyle.swift`, and `GlassWindow.swift` the window chrome.
- Views in lazy collections (`LazyVGrid`, `List`, `LazyVStack`): a row or tile reads only its own state. It takes plain values, not the shared `@Observable` model, for anything that changes often (selection, hover, the playing item), and is `Equatable` with `.equatable()`, so one change re-evaluates the few views whose values changed, not all of them.
- Put footers and status text that read such state in their own `View` structs, not computed properties of a big body.
- One interaction must cost the same however big the library is.
- Use a single `onTapGesture` and read `NSApp.currentEvent?.clickCount`. `onTapGesture(count: 2)` delays every single click (lint rejects it).
- UI and model types are `@MainActor`. Heavy work runs in `Task.detached`, and CG types cross actors through `@unchecked Sendable` wrappers (`SendableImage`, `EditorDocument`).
