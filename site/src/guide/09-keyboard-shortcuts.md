---
title: Keyboard shortcuts
summary: "Every shortcut in Shot, and how to change them."
group: Reference
---

## Global

These work in any app, while Shot is running:

| Shortcut | Action |
|---|---|
| <kbd>⌘⇧3</kbd> | Capture the full screen |
| <kbd>⌘⇧4</kbd> | Capture an area. Press <kbd>Space</kbd> to pick a window instead. |
| <kbd>⌘⇧5</kbd> | Record an area. Press <kbd>Space</kbd> to pick a window, or <kbd>Return</kbd> for the full screen. |

While you set up a recording, the record shortcut starts it. While you record, it stops the recording.

Shot takes these keys over from macOS while it runs, once it has Screen Recording access, unless you turned that off in the [welcome window](#follow-the-welcome-window). When Shot quits, macOS gets its keys back.

## Change a shortcut

1. Open **Settings › Shortcuts**.
2. Click a shortcut, then press the new keys. They must include <kbd>⌘</kbd>, <kbd>⌥</kbd> or <kbd>⌃</kbd>.
3. <kbd>Esc</kbd> cancels, and <kbd>Delete</kbd> clears the shortcut.

Shot won't take a shortcut that another action already uses, or <kbd>⌘Q</kbd>, <kbd>⌘W</kbd>, <kbd>⌘Tab</kbd>, <kbd>⌘Space</kbd>, <kbd>⌘H</kbd> or <kbd>⌘M</kbd>. **Restore Defaults** puts them all back, and turns **Use Shot for ⌘⇧3 to ⌘⇧5** back on.

## Keep the macOS screenshot tool

Turn off **Use Shot for ⌘⇧3 to ⌘⇧5** in **Settings › Shortcuts**. macOS gets its keys back, and Shot uses the same keys with <kbd>⌃</kbd> in place of <kbd>⌘</kbd>: <kbd>⌃⇧3</kbd>, <kbd>⌃⇧4</kbd> and <kbd>⌃⇧5</kbd>, plus <kbd>⌃⇧W</kbd> for a window.

> [!NOTE]
> If you turn the macOS shortcuts back on in System Settings, Shot stops using those keys until you turn **Use Shot for ⌘⇧3 to ⌘⇧5** on again.

## Actions you can give a shortcut

**Record Full Screen**, **Record Window**, **Pick Colour**, **Copy Latest Capture's Path**, **Capture Previous Area**, **Copy Text** and **Focus Quick Access** have no shortcut until you set one. Every one of them also has a [`shot://` link](#url-scheme).

- **Pick Colour** shows a loupe. Click any pixel on screen to copy its hex, such as `#1E90FF`.
- **Capture Window** has no shortcut while Shot uses ⌘⇧3 to ⌘⇧5. Press <kbd>Space</kbd> after <kbd>⌘⇧4</kbd> instead.

## While selecting

| Key | Action |
|---|---|
| Space | Switch between picking an area and picking a window. While dragging, hold it to move the area. |
| Return | Record the full screen (recording only) |
| Esc | Cancel |

## Recording setup

| Key | Action |
|---|---|
| Return | Start recording, after the countdown if one is set |
| Esc | Cancel |

## Recording

| Key | Action |
|---|---|
| ⌘Z | Undo a discard, for 5 seconds after it, whichever app is in front |

## Quick Access, after Focus Quick Access

| Key | Action |
|---|---|
| ↑ / ↓ | Choose a card |
| Return or ⌘C | Copy the card, then go back to your app |
| Space | Open the card's menu |
| ⌘S / ⌘E | Save As… / Annotate or Edit |
| Delete | Close the card |
| Esc | Go back to your app |

## Annotation editor

| Key | Action |
|---|---|
| V H A L R D T S M F B N C | Choose a tool (see [Pick a tool](#pick-a-tool)) |
| Shift / Option while drawing | Keep it square or at 45° / draw from the centre |
| Shift / Option / Space while dragging a handle | Keep proportions or 45° (free on an image) / resize from the centre / move the shape |
| Delete | Delete the selection |
| Esc | Deselect, cancel what you're drawing, or finish typing |
| Arrow keys | Nudge the selection 1 pixel (10 with Shift) |
| Arrow keys on a focused slider or colour field | Step it by 1% (10% with Shift). A held key is one undo step. Tab reaches sliders when Keyboard navigation is on in System Settings › Keyboard. |
| ⌘C | Copy the selected annotation, or the whole image |
| ⌘V | Paste an annotation or an image |
| ⌘D | Duplicate the selection |
| ⌥⌘C / ⌥⌘V | Copy / paste a style |
| ⇧⌘I | Add an image: a recent capture or a file |
| ⌘L | Show or hide the layers |
| Return in the layers | Rename the selected layer |
| ⌘] / ⌘[ | Move the selection forward / back |
| ⌥⌘] / ⌥⌘[ | Bring the selection to the front / send it to the back |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘+ / ⌘- | Zoom in / out |
| ⌘0 | Zoom to fit |
| ⌘1 | Actual size |
| Space-drag or middle-drag | Move around when zoomed in |
| ⌘S | Save and copy |
| ⌘W | Close, asking to save changes |

## Video editor

| Key | Action |
|---|---|
| Space | Play or pause |
| ← / → | Step back or forward one frame |
| ⇧← / ⇧→ | Step back or forward one second |
| Home / End | Go to the start / end |
| Shift-drag | Select a section of the timeline |
| S | Split the clips under the playhead |
| K | Key everything the selected clip or annotation can animate at the playhead, or take those keyframes away |
| N | Turn snapping on or off |
| T | Show or hide the tracks |
| C | Crop the selected clip, or the frame with nothing selected |
| Return | Apply the crop |
| Delete | Take away the selected keyframe, section, or clip or annotation |
| Esc | Cancel a crop or an export, clear the selected section, deselect, or stop annotating |
| ⌘] / ⌘[ | Move the selected annotation or clip a lane up / down |
| ⌥⌘] / ⌥⌘[ | Move the selected annotation or clip to the top / bottom lane |
| ⌘+ / ⌘− / ⌘0 | Zoom the timeline in / out / to fit |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘C | Copy the edited video |
| ⌥⌘C / ⌥⌘V | Copy / paste the selection's style |
| ⌘S | Save and copy |
| ⌘W | Close, asking to save changes |

## Gallery

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

## Any Shot window

| Key | Action |
|---|---|
| ⌘W | Close the window |
| ⌘, | Open Settings |
| ⌘Q | Quit Shot |
