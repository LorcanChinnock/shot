# Checklists

One pass per section, each in several states. A check is only done when you can say what you measured or saw. Reference
standards: Apple Human Interface Guidelines (macOS), WCAG 2.2 level AA, and the app's own design tokens (`Sources/Shot/Design/`).

Baseline for every pass: take a full-screen screenshot and a `uxqa_ax` dump *in that state*, in light and dark appearance
(`uxqa_appearance dark|light`).

States to cover for the video editor: fresh open · playing · clip selected · nothing selected · tracks panel on and off ·
inspector open · annotate mode with each tool · imports present · annotations present · exporting · export finished ·
GIF vs MP4 options · error toast showing · dirty and clean · after undo to the start.

---

## 1. Design (does it make sense?)

Heuristics: Nielsen's ten, HIG principles (clarity, deference, depth).

- [ ] **One obvious primary action** per state; destructive and secondary actions are visually lower weight.
- [ ] **State is visible**: what's selected, what's playing, what's dirty, what's disabled and *why* (a disabled control
      should explain itself without a tooltip being the only place).
- [ ] **Feedback for every action** within ~100 ms; anything over ~1 s shows progress, and the app shows what finished
      or failed. Check where the message appears (is it near the action, readable long enough, announced to VoiceOver?).
- [ ] **Controls look like what they do** (buttons look pressable, sliders drag, text is editable) and the same control
      means the same thing everywhere. Labels use verbs; icons have text or a tooltip.
- [ ] **Undo and escape hatches**: every edit undoable (⌘Z/⇧⌘Z), Esc backs out of modes and dialogs, closing with unsaved
      work asks, destructive actions are reversible or confirmed.
- [ ] **Error prevention and recovery**: impossible actions are unavailable or explained, errors say what happened and what
      to do, nothing fails silently.
- [ ] **Platform conventions**: standard shortcuts (⌘Z ⌘C ⌘S ⌘W ⌘, ⌘Q), menu bar items exist for window actions, window
      buttons and title-bar double-click behave, Tab/Shift-Tab and arrows work as expected, drag and drop where users expect it.
- [ ] **Microcopy**: sentence case, no jargon, consistent terms (Save vs Export vs Copy are distinct and explained), no
      truncated sentences, numbers with units.
- [ ] **Discoverability**: can a new user find split, import, annotate, keyframes, export options without being told?
      Shortcuts are shown in tooltips and menus.
- [ ] **Empty, loading and edge states** have designs (no clips selected, no thumbnails yet, zero keyframes, nothing to undo).
- [ ] **Persistence**: remembered options (format, fps, width, tool, colour) are remembered *visibly* and make sense on next launch.

## 2. Alignment (are things where the eye expects them?)

Misalignment by a few points is the most common visual bug and the easiest to miss by eye. Measure it.

**Procedure**
1. List every row and column in the screen: header row, toolbar row, inspector row, transport row, options row, etc.
2. For each, write down what should share an axis: centre line (items in a row), left edge (items in a column), baseline
   (text next to text), or right edge. Items in one row should share a centre line and, for the same kind of control, a height.
3. Measure. Standard controls: `uxqa_ax` frames (centre y = y + h/2). Custom-drawn: `measure FILE X Y W H` on a crop of
   each item and compare the printed centres and edges. Tolerance is **0 pt for intended alignment, 0.5 pt for rounding**.
   Anything within 1–6 pt of lining up but not lining up is a bug, not a style.
4. `uxqa_ax` already flags row and left-edge near-misses; read each, and decide whether it's real.

**Checks**
- [ ] Controls in a row share a centre line (header buttons, toolbar buttons, option segments, tool palette, inspector captions,
      sliders and their value labels, diamonds and their sliders).
- [ ] **A transport or leading control aligns with the thing it controls.** The play button's centre must equal the centre of
      the main track's row (not the ruler, not the whole lanes block), in every state: with 0, 1 and several lanes above the
      main one, with the inspector open, with the lanes capped and scrolling.
- [ ] Left and right edges of stacked blocks line up: preview edges vs timeline vs toolbar vs options bar; the lane's left edge
      vs ruler tick 0:00 vs the playhead at 0; the right edge vs the last tick/clip end.
- [ ] The playhead's line passes through the time it claims: its x equals the ruler tick for that time, in the ruler, every lane,
      and the preview's time readout.
- [ ] Clip edges, trim handles, keyframe diamonds and selection rectangles land on the times the readouts show (check at zoom
      1× and zoomed in), and thumbnails don't drift relative to their clips.
- [ ] Text baselines match for text of different size sharing a row (title and badge, caption and value).
- [ ] Icon and label are centred on each other inside buttons; button label padding is equal left and right.
- [ ] Spacing follows the token scale (see `Brutal` tokens, 4/8 pt grid): equal gaps between equal items, gutters equal on both
      sides, the same inset from the window edge on all sides.
- [ ] Optical alignment: circles and diamonds look centred (size matters), shadows don't shift apparent edges.
- [ ] Alignment holds in **every state and at every window size**. Layout changes (selection, panel toggles, resize) must not
      leave one element behind: re-measure after each.

## 3. Layout (is the structure sound?)

- [ ] **Hierarchy and grouping**: related controls sit together, groups are separated by more space than their members,
      reading order matches importance (top-left to bottom-right) and matches tab order.
- [ ] **Nothing overlaps, clips or hides**: no control under another, text not cut at the window or container edge, shadows
      and focus rings not clipped, popovers and toasts not covering what they refer to.
- [ ] **Space is used for the task**: the preview, the main focus, keeps the most room; chrome stays proportionate. Record the
      preview's height in each state; it must not collapse when panels open.
- [ ] **Windows grow and shrink predictably**: opening a panel doesn't move the window off-screen, doesn't cover the dock
      or menu bar, keeps the top edge where the user left it, and closing restores the size.
- [ ] **Scrolling**: content taller or wider than its container scrolls instead of squeezing; scroll position is sensible after
      state changes; scroll indicators and trackpad gestures behave; no nested scroll traps.
- [ ] **Z-order and modality**: sheets attach to their window and block it; non-modal panels don't steal keys; the toast layer
      sits above everything and is dismissible.
- [ ] **Consistency across screens**: the same pattern uses the same layout in the editor, annotator, gallery and settings.
- [ ] Layout is **stable**: no jumping when hovering, selecting, or when numbers change width (use monospaced digits).

## 4. Size responsiveness (does it hold at every size?)

**Matrix.** Test at least: the window's minimum size; a 13" laptop (visible area about 1440×875) and a 14" (1512×982)
with the window as large as it will go; a large external display (2560×1440 and up); a very short window; and display scaling
set to "More Space" and "Larger Text" if you can switch it. Resize two ways: with accessibility (`uxqa_resize W H`, fast, but
**bypasses `minSize`**) to probe the layout, then with a real drag of the window edge to confirm what a user can reach.

For each size and each state:
- [ ] The window respects its minimum size when dragged, and the minimum is large enough that nothing breaks. If the screen
      is smaller than the minimum, the minimum is clamped to the screen.
- [ ] **No text wraps or truncates unintentionally** (labels such as "Tracks", captions like "WIDTH", the time readout, the
      size estimate, badges). Titles may truncate in the middle; controls and numbers must not.
- [ ] **The key content keeps a usable size** (preview at least ~200 pt tall; lanes keep the ruler and the main lane, scrolling
      the rest).
- [ ] **Controls keep their size and spacing**; rows that don't fit reflow or scroll rather than overlapping.
- [ ] Content at extremes: very long file names, 1-second and 2-hour videos, portrait and ultra-wide aspect ratios, tiny clips,
      10+ tracks, annotations at the canvas edge. Zoom to its limits at both ends.
- [ ] Live resize is smooth (no flicker or stale ghost frames, content redraws) and the layout recovers after growing back.
- [ ] Multi-display and screen changes: moving the window between displays, a different scale factor, a display unplugged.
- [ ] Fullscreen and tiling (Stage Manager, split view) don't break the layout.

## 5. Accessibility (WCAG 2.2 AA and Apple's guidance)

Run `uxqa_ax` and work through its problem list first; then these.

- [ ] **Name, role, value (4.1.2)**: every interactive element has a meaningful name that isn't just its visible glyph;
      sliders and steppers expose their value; toggles expose on/off; custom views have a role and a value.
- [ ] **Custom controls are operable by assistive tech**: timelines and canvases expose an adjustable action or named actions
      (seek ±1 s, split, delete clip), and a value that reads "0:03 of 0:10".
- [ ] **Keyboard operability (2.1.1)**: the whole task can be done without a pointer; every shortcut is discoverable; Tab order
      follows the visual order (`uxqa_keycode 48` repeatedly, screenshot each stop); no keyboard traps (2.1.2); Esc closes
      transient UI; shortcuts don't fire while typing in a text field.
- [ ] **Focus is visible (2.4.7, 2.4.11)** and not hidden behind other content.
- [ ] **Contrast**: text and icons ≥ **4.5:1** (≥ 3:1 for text ≥ 18 pt or ≥ 14 pt bold), UI component boundaries, focus rings,
      and state indicators ≥ **3:1** (1.4.3, 1.4.11). Sample the colours (`measure FILE sample X Y`, on a flat pixel of
      the glyph and of its background) and compute: relative luminance L = 0.2126 R + 0.7152 G + 0.0722 B, with each channel
      c ← (c/255 ≤ 0.03928 ? c/12.92 : ((c/255+0.055)/1.055)^2.4); ratio = (L₁+0.05)/(L₂+0.05), lighter over darker. Check
      disabled, hover, selected and over-video states, in light and dark.
- [ ] **Not colour alone (1.4.1)**: selected, error, dirty and disabled states also differ by shape, text or weight.
- [ ] **Target size (2.5.8)**: pointer targets ≥ 24×24 pt (aim for 28+ for dense toolbars) with spacing; small handles have a
      larger hit area than their drawing.
- [ ] **Text**: ≥ 11 pt for anything essential; it scales or reflows with system text size where the platform allows;
      no text in images.
- [ ] **Reduce Motion / Reduce Transparency / Increase Contrast**: toggle each in System Settings › Accessibility › Display and
      re-check; animations that move things respect Reduce Motion; translucent backgrounds keep contrast when transparency
      is reduced.
- [ ] **Status messages (4.1.3)**: toasts and progress are announced to VoiceOver and stay long enough to read (≥ 5 s or
      persistent for errors).
- [ ] **Tooltips aren't the only place** for essential information (they're invisible to touch and many AT users).
- [ ] **Timing**: nothing times out unexpectedly; auto-dismissing UI can be paused.
- [ ] Don't use drag as the only way (2.5.7): trim, move and reorder have a keyboard or button alternative.
- [ ] VoiceOver walk-through if possible: ⌘F5, then VO+Right through the window; it reads sensibly and in a logical order.

## 6. Aesthetics (does it look finished and coherent?)

Judge against the app's own design system first; it has a deliberate style (see `Sources/Shot/Design/`).

- [ ] **Tokens, not one-offs**: colours, corner radii, border widths, shadow offsets and fonts all come from the shared set.
      Spot-check with zoomed crops; two nearly-the-same radii or greys are a defect.
- [ ] **Typographic hierarchy**: a small number of sizes and weights; captions, values and titles are clearly distinct;
      numbers use a monospaced face where they change.
- [ ] **Iconography**: one style and weight, optically the same size, correct metaphors, crisp at 2× (no blur or half-pixel edges).
- [ ] **Spacing rhythm and density**: consistent gaps, no cramped clusters beside large empty areas, balanced margins.
- [ ] **Colour use**: meaning is consistent (the same colour means the same thing), accents are used sparingly, nothing garish
      against the video content, dark and light appearances both feel designed.
- [ ] **States are distinct and polished**: default, hover, pressed, focused, selected, disabled and loading all look intentional
      (take a screenshot of each for at least the primary buttons and segmented controls).
- [ ] **Motion**: transitions are quick (~150–300 ms), eased and purposeful, never block input, and don't jank during playback.
- [ ] **Edges and artefacts**: no clipped shadows or borders, no seams between adjacent shapes (look at joins at 2×), no stale
      pixels after resize or undo, no flicker on state change, no text rendering oddities, correct rounded-window corners.
- [ ] **Content presentation**: letterboxing is clean, thumbnails are sharp and match their time, waveforms are legible,
      overlays and annotations render the same in the preview and in the export.
- [ ] Capture 2× crops of each region and look at them at full size, not only at screen scale.
- [ ] **Ink edges on a 1x display**: Retina hides half-pixel faults. On a 1x screen, sample the pixels across borders and
      corners: the outermost pixel must be ink at partial alpha, never a lighter colour from inside, and borders must be
      whole pixels with no grey seam between fill and ink.

## 7. Functional QA (does it do what it says?)

- [ ] Every control does what its label and tooltip say, in every state it's enabled; every shortcut in `docs/usage.md` works.
- [ ] **Edit operations** (split, delete, move, trim, cut, import, annotate, keyframe, transform) change the preview *and*
      the timeline and the output the same way. After each, undo and redo restore exactly the previous state, repeatedly, and
      to the very start and end of the history.
- [ ] **Boundaries**: split at the first and last frame, at an existing split, in a gap; delete the only clip; trim to the
      minimum; move past the ends; zoom to the limits; scale and opacity at their extremes; overlapping clips and annotations.
- [ ] **Rapid and concurrent input**: spam keys and clicks, double-click Export, edit during an export, quit or close mid-export,
      start a second editor on the same file.
- [ ] **Interruption and cancel**: cancel every dialog and picker, close with unsaved edits (Save, Discard, Cancel all work),
      reopen after discard, files deleted or moved while open.
- [ ] **Inputs**: unusual media (portrait, odd frame rates, no audio, audio only, very short, very long, unreadable, huge),
      long and unicode file names, read-only locations.
- [ ] **Outputs match the edit**: probe every file written (`ffprobe` duration, resolution, fps, streams; `volumedetect`),
      extract frames at the interesting times and check the content, the order, the overlay and annotation timing, the
      crop, the speed, the mute option. Compare duration against the timeline's own readout. GIFs: frame count, delays
      (they're whole hundredths of a second), looping, width.
- [ ] **Persistence and side effects**: remembered options, recent files, the clipboard after Copy and Export, the
      originals are untouched unless Save was chosen.
- [ ] **Messages are true**: what a toast or label claims (saved, copied, size, duration) is what happened.
- [ ] **Transitions hold still**: record every toggle and picker change in both directions (`screencapture -v -V 3 -R…`,
      then `ffmpeg` to frames) and track a few card edges and labels frame by frame. Anything that jumps for an update and
      then settles is a glitch a still screenshot misses, usually a view mixing two copies of the same state that update at
      different times.

## 8. Robustness and performance

- [ ] Scrubbing, dragging and zooming keep up with the pointer on a long clip; playback doesn't stutter; thumbnails and
      waveforms load without blocking the UI.
- [ ] Idle CPU is near zero when nothing plays; memory doesn't climb over repeated open/close and repeated exports.
- [ ] Long operations are cancellable or at least don't hang the app; the app recovers from a failed export.
- [ ] **Logs and crashes**: `log show --last 10m --predicate 'process == "Shot"' --style compact | grep -iE "error|fault"`, and
      look for new files in `~/Library/Logs/DiagnosticReports/` after the session. Any new crash report is an S1.
- [ ] Nothing the session wrote is left behind in the user's folders: remove your test exports, or report where they are.
