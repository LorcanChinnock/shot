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

- **Say so first.** Tell the user the session is about to take over the mouse, keyboard and screen, and that they should not type
  into other windows while it runs. If you see their terminal or another app taking focus mid-run, stop driving and ask. Never
  keep clicking: a click or a keystroke into the wrong app is the real hazard here.
- **Focus guard.** `scripts/input.swift` refuses to click unless the app under test is frontmost, and every helper in
  `session.sh` re-raises the window first. `open`/`activate` do not reliably take focus while someone is typing; setting
  `frontmost` and `AXRaise` through System Events does. Keystrokes (`uxqa_key`) have no guard of their own, so always follow
  `uxqa_focus` with a screenshot that proves where the focus is before typing anything.
- **Test the build under review, and only that.** Kill every running copy first (an installed release registers the `shot://`
  scheme and silently answers URLs meant for your build, which makes you test the wrong binary). Launch with an absolute
  path: `open -a /abs/path/Shot.app` (a relative path is looked up as an app *name*). Confirm the running binary's path.
- **Work in a worktree** (`~/dev/worktrees/…`), never the main checkout. Don't commit, push, or touch the user's settings,
  captures or other apps. Put test media and screenshots in the scratchpad, not the user's folders. Quit the app you launched
  when you finish unless the user wants to look.
- **Permissions.** The terminal needs Accessibility (input, `axdump`) and Screen Recording (screenshots). If they're missing,
  say which and stop; don't work around them.

## 1. Set up

```sh
cd <worktree>
make bundle                                   # build the app under test → build/Shot.app
source .agents/skills/ux-qa/scripts/session.sh
uxqa_setup                                    # compiles the input, axdump and measure tools
.agents/skills/ux-qa/scripts/make-clips.sh "$UXQA_DIR/clips"     # 10 s 720p, 6 s 1080p, 3 s portrait, all with sound
uxqa_launch "shot://edit-video?path=$UXQA_DIR/clips/a.mp4"
```

Other entry points: `shot://annotate?path=`, `shot://gallery`, `shot://settings?section=`. See `docs/usage.md`. Screen
capture and recording need real permissions and a person, so test the editors on files and say that capture itself was out of scope.

**Units.** Everything is in screen *points*. `uxqa_shot` writes images at point size (1 px = 1 pt), `axdump` reports frames in
points, and `input` takes points, so a coordinate read off a screenshot can be clicked directly. Don't mix in raw Retina
screenshots. Re-take the screenshot after every layout change (selecting a clip, opening a panel and resizing all move things).

**What can and can't be driven.**
- Standard controls: buttons, menus, text fields show up in `axdump` with frames. Accessibility presses reach them.
- Custom-drawn views (timelines, canvases, lanes) are one opaque element to accessibility and **ignore accessibility
  presses**. Use real mouse events (`uxqa_click`, `uxqa_drag`, `uxqa_scroll`). Measure them from screenshots with `measure`.
- Sheets and open panels (`NSOpenPanel`): ⌘⇧G, type the path, Return selects the file, then click **Open** (a second Return is
  often swallowed). Screenshot after each step; typed text and key presses can be dropped, and the menu behind an Import
  button needs its own click before the panel appears.

## 2. The session

1. **Recon.** Read `docs/usage.md` for the intended behaviour and the keyboard shortcuts, skim the view code for the screen
   under test so you know which things are *supposed* to line up, and take an `axdump` baseline. Write down expectations
   before you look at pixels.
2. **Golden path as a first-time user.** Open a clip, play it, trim, split, delete, undo, import, annotate, export, close.
   Note every moment of hesitation: unlabelled controls, unclear state, silent failures. Take a full-screen screenshot after
   each step; feedback such as toasts sits at the bottom edge of the screen, outside the window.
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
  `measure win.png sample X Y` reads a colour for contrast maths.
- Compare against the code's intent. If a button is meant to sit on the main track's row, the rule is "centres equal", and
  you can measure it. If you can't state the rule, you can't call it a bug.
- Always take the screenshot for a claim *after* the final state settles (sleep ~0.5 s for animations).

## 4. Before you report a finding

Most false findings come from the test rig. For each candidate:
1. **Reproduce it** a second time from a clean launch.
2. **Look at the whole screen**, not a crop: you may have missed the toast, the dialog or the other window that explains it.
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
  ⌫ delete/cut, Esc clear, ⌘Z/⇧⌘Z, ⌘S save, ⌘C copy, ⌘+/⌘−/⌘0 zoom. Annotation tools use letter keys (see `docs/usage.md`).
- Exports land next to the source video as `Shot <date> at <time>.<ext>` and a toast reports them at the bottom of the screen.
- The main track's strip, lanes, ruler and the playhead are one custom view; the play button sits beside it and should be
  centred on the main track's row. The trim handles, lanes and playhead need real mouse drags.
- Size estimates (`≈ N MB`) are heuristics tuned for real screen recordings; don't judge them against synthetic clips.
- Settings that persist between launches (export format, GIF fps and width) change what you see on the next launch; note them.
