# Keyboard shortcuts

## Global

Every capture and recording action, **Pick Colour**, **Copy Latest Capture's Path**, **Capture Previous Area**, **Copy Text** and **Focus Quick Access** can have a global shortcut and a [`shot://` URL](#url-scheme). Unless you turned it off in the [welcome window](#first-launch), Shot takes over the macOS screenshot keys and turns off the matching macOS shortcuts while it runs, once it has Screen Recording access. When Shot quits, macOS gets its keys back. If you turn the macOS shortcuts back on in System Settings, Shot stops using those keys until you turn **Use Shot for ⌘⇧3 to ⌘⇧5** on again.

| Shortcut | Action |
|---|---|
| ⌘⇧3 | Capture the full screen |
| ⌘⇧4 | Capture an area. Press Space to pick a window instead. |
| ⌘⇧5 | Record an area. Press Space to pick a window, or Return for the full screen. |

While you set up a recording, the record shortcut starts it. While you record, it stops the recording. You can change any shortcut in **Settings › Shortcuts**: click a shortcut, then press the new keys, which must include ⌘, ⌥ or ⌃. Esc cancels and Delete clears it. Shot won't accept a shortcut that another action already uses, or ⌘Q, ⌘W, ⌘Tab, ⌘Space, ⌘H or ⌘M. **Restore Defaults** puts them all back, and turns **Use Shot for ⌘⇧3 to ⌘⇧5** back on.

To keep the macOS screenshot tool, turn off **Use Shot for ⌘⇧3 to ⌘⇧5** in **Settings › Shortcuts**. macOS gets its keys back, and Shot uses the same keys with ⌃ in place of ⌘: ⌃⇧3, ⌃⇧4, ⌃⇧5, plus ⌃⇧W for a window.

Record Full Screen, Record Window, Pick Colour, Copy Latest Capture's Path, Capture Previous Area, Copy Text and Focus Quick Access have no shortcut until you set one. Pick Colour shows a loupe; click any pixel on screen to copy its hex, such as `#1E90FF`. Capture Window has none while Shot uses ⌘⇧3 to ⌘⇧5; press Space after ⌘⇧4 instead.

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
| V H A L R D T S M F B N C | Choose a tool (see [Tools](#tools)) |
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
