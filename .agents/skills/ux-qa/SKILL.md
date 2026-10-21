---
name: ux-qa
description: Run a full UX and QA session on Shot by driving the real app like a user. Covers design, alignment, layout, size responsiveness, accessibility, aesthetics and functional correctness, with measured evidence for every finding. Use when asked to "test", "QA", "dogfood", "review the UX of" a screen or feature, or after a UI change to check for regressions.
---

# UX and QA session

Drive the real, built app the way a person would, then judge it against industry standards, not taste. Every finding needs
evidence (a screenshot, a measurement or a file you probed) and, before it is reported, a check that it isn't an artefact of the
test setup. A visual eyeball pass misses the bugs that matter most: things a few points out of line, text clipped at one window
size, controls with no accessible name. So each dimension below has its own checks in [checklists.md](checklists.md), and
alignment, layout and size are measured, not eyeballed.

Pass scope: the feature the user named, or if none, the whole app. Pretend to be a first-time user *and* a power user.

## 0. Rules for driving someone's machine

This runs on a real desktop that the person may be using at the same time.

- **Stay out of the way.** Drive the app with `shot-dev://` URLs (`uxqa_open`) and accessibility, and capture only its window
  (`uxqa_shot`), which works while it sits behind other windows, so the user keeps working in their own app. Take focus or the
  screen only when a check truly needs it: clicks, drags, scrolls and keystrokes (custom-drawn views, shortcuts, sheets),
  toasts and Quick Access cards (their own windows, at the screen's edge), the capture overlay (full screen by nature), and
  recording a transition. Batch those steps together.
- **Say so first.** Before the first step that takes focus, tell the user the session is about to use the mouse, keyboard and
  screen, and that they should not type into other windows while it runs. If you see their terminal or another app taking focus mid-run, stop driving and ask. Never
  keep clicking: a click or a keystroke into the wrong app is the real hazard here.
- **Focus guard.** `scripts/input.swift` refuses to click unless the app under test is frontmost, and every helper in
  `session.sh` re-raises the window first. `open`/`activate` do not reliably take focus while someone is typing; setting
  `frontmost` and `AXRaise` through System Events does. Keystrokes (`uxqa_key`) have no guard of their own, so always follow
  `uxqa_focus` with a screenshot that proves where the focus is before typing anything.
- **Hand focus back.** When the last step that takes focus is done, and before you write the report, bring the terminal or app
  you run in back to the front, so the user knows they can take over again. Find it by walking up your shell's parent processes
  to the first `*.app`, raise it with `open -a <that app>`, and confirm with `lsappinfo info -only name $(lsappinfo front)`.
- **Test the build under review, and only that.** Kill every running ShotDev first (another copy, such as one `make app`
  installed, registers the same `shot-dev://` scheme and silently answers URLs meant for your build, which makes you test the
  wrong binary). An installed release answers `shot://` only, so it can keep running. Launch with an absolute path:
  `open -a /abs/path/ShotDev.app` (a relative path is looked up as an app *name*). Confirm the running binary's path.
- **Work in a worktree** (`~/dev/worktrees/…`), never the main checkout. Don't commit, push, or touch the user's settings,
  captures or other apps. Put test media and screenshots in the scratchpad, not the user's folders. Quit the app you launched
  when you finish unless the user wants to look.
- **Permissions.** The terminal needs Accessibility (input, `axdump`) and Screen Recording (screenshots). If they're missing,
  say which and stop; don't work around them.

## 1. Set up

```sh
cd <worktree>
make bundle                                   # build the app under test → build/ShotDev.app
source .agents/skills/ux-qa/scripts/session.sh
uxqa_setup                                    # compiles the input, axdump and measure tools
.agents/skills/ux-qa/scripts/make-clips.sh "$UXQA_DIR/clips"     # 10 s 720p, 6 s 1080p, 3 s portrait, all with sound
uxqa_launch "shot-dev://edit-video?path=$UXQA_DIR/clips/a.mp4"   # starts in the background, without taking focus
uxqa_shot editor                              # the app's window only, even behind others
```

If each of your shell calls starts a fresh shell, the sourced helpers are gone by the next call. Run them through `qa` instead.
It works from any directory, drives that worktree's `build/ShotDev.app`, and compiles the tools when they're missing or stale:

```sh
.agents/skills/ux-qa/scripts/qa 'uxqa_launch "shot-dev://gallery"'
.agents/skills/ux-qa/scripts/qa 'uxqa_open "shot-dev://settings?section=general"; uxqa_shot settings'
.agents/skills/ux-qa/scripts/qa 'uxqa_click 640 320; sleep 0.5; uxqa_shot after-click'
```

Other entry points: `shot-dev://annotate?path=`, `shot-dev://gallery`, `shot-dev://settings?section=`. See `site/src/guide/10-url-scheme.md`. Screen
capture and recording need real permissions and a person, so test the editors on files and say that capture itself was out of scope.

**Units.** Everything is in *points*. `uxqa_shot` writes the window at point size (1 px = 1 pt) and prints the window's screen
origin; `axdump` reports frames and `input` takes screen points, so a point read off a screenshot is clicked at origin + pixel.
`uxqa_screen` images are in screen points already. Don't mix in raw Retina screenshots. Re-take the screenshot after every layout change (selecting a clip, opening a panel and resizing all move things).

**What can and can't be driven.**
- Standard controls: buttons, menus, text fields show up in `axdump` with frames. Accessibility presses reach them.
- Custom-drawn views (timelines, canvases, lanes) are one opaque element to accessibility and **ignore accessibility
  presses**. Use real mouse events (`uxqa_click`, `uxqa_drag`, `uxqa_scroll`). Measure them from screenshots with `measure`.
- Sheets and open panels (`NSOpenPanel`): ⌘⇧G, type the path, Return selects the file, then click **Open** (a second Return is
  often swallowed). Screenshot after each step; typed text and key presses can be dropped, and the menu behind an Import
  button needs its own click before the panel appears.

## 2. The session

1. **Recon.** Read the user guide in `site/src/guide/` for the intended behaviour and the keyboard shortcuts, skim the view code for the screen
   under test so you know which things are *supposed* to line up, and take an `axdump` baseline. Write down expectations
   before you look at pixels.
2. **Golden path as a first-time user.** Open a clip, play it, trim, split, delete, undo, import, annotate, export, close.
   Note every moment of hesitation: unlabelled controls, unclear state, silent failures. Take a window screenshot after
   each step. Feedback such as toasts sits at the bottom edge of the screen, outside the window: find it with `uxqa_windows`
   and capture it with `uxqa_shot NAME -w ID`, or `uxqa_screen` if it's gone too fast. ShotDev's "Hide Shot from captures"
   setting keeps toasts and Quick Access cards out of every capture, so turn it off in ShotDev's Settings to see them.
3. **Dimension passes.** Work through each section of [checklists.md](checklists.md) *in its own pass*, in this order:
   Design, Alignment, Layout, Size responsiveness, Accessibility, Aesthetics, Functional, Robustness. Do each in several
   states (nothing selected, a clip selected, panels open, multiple tracks, exporting, disabled), because most defects hide
   in the states nobody opens.
4. **Abuse.** Rapid repeated input, double-clicking everything, acting during an export, cancelling dialogs, undo past the
   start, huge and tiny values, odd media (portrait, audio-only, zero-length, unreadable), closing with unsaved work.
5. **Verify outputs, not just UI.** Anything the app writes gets probed: `ffprobe` for duration, size, frame rate and streams;
   extract frames at the interesting times and look at them; `volumedetect` for audio. A UI that says "Exported" proves nothing.
6. **Check your findings** (section 4), then report (section 5).

## 3. Reading the evidence

- `uxqa_ax` lists the accessibility tree and flags unnamed controls, targets under 24 pt, controls outside their window,
  overlaps, and *near-misses*: things a few points off a shared row or edge. A near-miss is almost always a bug.
- Anything the tree can't see needs `measure`: `measure win.png X Y W H` prints the bounding box, centre, and the runs of
  content inside a rect, so "the play button looks off" becomes "its centre is 36 pt above the main track's centre".
  `measure win.png sample X Y` reads one pixel's colour.
- For contrast, use `uxqa_contrast X Y W H [#bg]` with the rect in screen points around one glyph or line. It captures at full
  resolution and prints the WCAG ratio of the pixel that differs most from the background (the rect's top-left pixel, or
  `#bg`). Don't measure contrast on a `uxqa_shot` image: it's scaled down, and the blur lightens thin strokes.
- Compare against the code's intent. If a button is meant to sit on the main track's row, the rule is "centres equal", and
  you can measure it. If you can't state the rule, you can't call it a bug.
- Always take the screenshot for a claim *after* the final state settles (sleep ~0.5 s for animations).

## 4. Before you report a finding

Most false findings come from the test rig. For each candidate:
1. **Reproduce it** a second time from a clean launch.
2. **Look at every window**, not a crop: `uxqa_windows` lists the toast, dialog or other window that may explain it
   (`uxqa_screen` if you need it in context).
3. **Read the code** that produces the behaviour. Is it a bug, a documented heuristic (like a size *estimate*), or intended?
   A claim you can't tie to code or a measurement is a hypothesis; label it "unconfirmed".
4. **Rule out the rig**: a window resized through accessibility bypasses `minSize`, so confirm size findings with a real
   drag; synthetic test clips are noise and make size estimates look wrong; an installed copy may be answering instead of your build.
5. If a finding turns out wrong, **say so plainly** in the report. Retracting is part of the job.

## 5. Report

Lead with what was tested (build, window sizes, states) and what was *not*. Then findings, worst first, each:

```
[S2] Short title: what is wrong, in one line
Where:    screen / state / window size
Evidence: screenshot path, measurement ("play centre y 172 vs main lane centre y 211"), or probed output
Standard: the rule it breaks (WCAG 2.2 SC 1.4.3, HIG, "shared centre line")
Cause:    file:line when known, otherwise "unconfirmed"
Fix:      the smallest change that would do it
```

Severity: **S1** loses or corrupts the user's work, crashes, or blocks a core task. **S2** breaks a standard (accessibility,
clipping, misalignment, wrong output) or confuses a core flow. **S3** polish, minor inconsistency. Keep opinions about taste
in a separate short list marked as such.

## 6. Fixing, if asked

Fix the smallest thing that removes the cause, put pure logic in `ShotCore` with a unit test (`make test`), rebuild, and
**re-run the exact repro** from the finding, with before and after images or numbers. Re-run the alignment and size
passes on the states you touched, because layout fixes shift their neighbours. Finish by running `uxqa_ax` again and
confirming the problem count only went down.

## Shot specifics

- Video editor shortcuts: Space play/pause, ←/→ frame, ⇧←/⇧→ one second, S split, K keyframes, T tracks, N snapping,
  ⌫ delete/cut, Esc clear, ⌘Z/⇧⌘Z, ⌘S save, ⌘C copy, ⌘+/⌘−/⌘0 zoom. Annotation tools use letter keys (see `site/src/guide/09-keyboard-shortcuts.md`).
- Exports land next to the source video as `Shot <date> at <time>.<ext>` and a toast reports them at the bottom of the screen.
- The main track's strip, lanes, ruler and the playhead are one custom view; the play button sits beside it and should be
  centred on the main track's row. The trim handles, lanes and playhead need real mouse drags.
- Size estimates (`≈ N MB`) are heuristics tuned for real screen recordings; don't judge them against synthetic clips.
- Settings that persist between launches (export format, GIF fps and width) change what you see on the next launch; note them.
