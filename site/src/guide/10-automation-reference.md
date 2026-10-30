---
title: Automation reference
summary: "Every shot:// link, for launchers, the Shortcuts app and scripts."
group: Reference
---

## URL scheme

Every action in Shot has a `shot://` link, so you can run it without the keyboard: from a launcher, the Shortcuts app, or a script.

### Try it

Open Terminal and run:

```sh
open "shot://capture-area"
```

Shot starts an area screenshot, just as <kbd>⌘⇧4</kbd> does.

### Every link

| URL | Action |
|---|---|
| `shot://screenshot` | Open the screenshot overlay, where Tab picks an area, window, browser page or full screen |
| `shot://capture-area`, `capture-window` | Take a screenshot, starting on an area or a window |
| `shot://capture-fullscreen` | Take a screenshot of the screen under the pointer at once |
| `shot://record` | Open the recording overlay, or confirm or stop a recording |
| `shot://record-window` | Record, starting on a window |
| `shot://record-fullscreen` | Record the screen under the pointer |
| `shot://pause` | Pause or resume the recording |
| `shot://pick-color` | Pick a colour on screen and copy its hex |
| `shot://copy-path` | Copy the newest capture's path |
| `shot://capture-timer?seconds=<n>` | Count down `n` seconds (1 to 60, default 5), then capture the full screen |
| `shot://annotate?path=<file>` | Open an image in the editor, or a video in the video editor |
| `shot://edit-video?path=<file>` | Open a video in the video editor to trim it |
| `shot://gallery` | Open the gallery |
| `shot://settings?section=<name>` | Open Settings at `gallery`, `general`, `capture`, `quickAccess`, `recording`, `shortcuts`, or `about` |
| `shot://welcome` | Open the [welcome window](#follow-the-welcome-window) again |

### Paths and errors

- `path` can start with `~`.
- URL-encode spaces and other special characters, for example `open "shot://annotate?path=~/Desktop/My%20Shot.png"`.
- The older `shot://record?full=1` still works, and does the same as `shot://record-fullscreen`.
- An unknown action or settings section, or `annotate` or `edit-video` without a `path`, shows an error instead.
