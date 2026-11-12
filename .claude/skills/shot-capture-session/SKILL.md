---
name: shot-capture-session
description: Drive ShotDev with computer use, using the ShotDemo sample app to reshoot guide media in docs/media. Use for "reshoot", "update the screenshots", "re-record the GIFs", or any task that needs pictures of Shot's own windows for the guide or site. For QA runs, use the same steps with the MugCo sample app (`make demo`) instead of ShotDemo.
---

# Driving Shot with computer use

Read CLAUDE.md's "Running and testing locally" and "Capturing something in QA and screenshots" first. ShotDemo is only for the media in `docs/media`. QA runs and one-off captures use MugCo (`make demo`, window "Mug Co. Support", process `MugCo`). This skill adds what goes wrong when computer use drives Shot, and it applies to both.

## Set up

1. **Run ShotDev from Xcode with the `run-shotdev` skill.** Its Run quits every other ShotDev and the installed Shot, so `scripts/dev.sh status` should then list exactly one ShotDev. Send every `shot-dev://` link with `scripts/shotdev-open.sh`.
2. **Wrap ShotDemo in an app bundle.** `swift run ShotDemo` makes a bare executable, and `request_access` rejects it as "not installed or running". Build it with `cd docs/demo && swift build -c release`, then make `ShotDemo.app` in the scratchpad (not the repo): `Contents/MacOS/ShotDemo` is the binary, `Contents/Info.plist` sets `CFBundleIdentifier` `dev.lorcan.ShotDemo`, `CFBundleExecutable`, `CFBundleName` and `CFBundlePackageType` `APPL`, then `codesign -s - --force`. Launch it with `open ShotDemo.app --args --scene article --appearance light`. Scenes are listed in `docs/demo/README.md`.
3. **Request access by name or bundle id:** `ShotDemo` (or `MugCo` for a QA run, wrapping it the same way if the request says it isn't installed or running), and `dev.lorcan.Shot.dev` for ShotDev. ShotDev is a menu bar app that only counts as a running app while one of its windows is open (it switches itself to a regular app then), so with nothing open `request_access` says it "doesn't match any installed or running application", under its display name too. Run `scripts/shotdev-open.sh 'shot-dev://gallery'` first, then request access, and keep a window open until you have the grant. A wrapper app doesn't help, because screenshots are filtered by the app that owns each window. Don't request a terminal: it is click-only and can't type.
4. **First launch needs the user.** ShotDev starts on the welcome window and macOS needs Screen Recording turned on for it. Never change that setting yourself. Ask the user to grant it and relaunch. `make reset-tcc` undoes it, so avoid that.

## Drive it

- `⌘⇧4` opens the overlay once ShotDev has permission. Keys: `S` toggles Scroll, `Tab` cycles Area, Window, Browser and Screen. Chips are clickable. `shot-dev://gallery` and `shot-dev://settings?section=general` open windows without a keyboard.
- **Key presses and clicks go to the frontmost app.** If a terminal is frontmost, `Escape` and `Return` do nothing. Click the ShotDemo window first.
- **Esc may not reach Shot while computer use drives the Mac.** In the #1080 session no Esc reached any of Shot's overlays, whether it came from computer use, a synthetic key event or the user's keyboard, while Return and the arrow keys did. Check a change to Esc handling against an Esc that's known to work, such as closing the capture overlay, and ask the user to try it by hand once the session is over.
- **A Shot overlay can miss computer use's key presses.** The overlays are panels that take the keyboard without making ShotDev the frontmost app, and computer use can send its keys to the app it thinks is in front. If a key does nothing, check the console for it first, then post it as a real key event with a small CGEvent script (`CGEvent(keyboardEventSource:virtualKey:keyDown:)` posted to `.cghidEventTap`). That reaches the overlay.
- **Banners block clicks.** A macOS notification such as "Login Item Added" makes clicks fail with "would land on Notification Centre". Wait for it to go, or use the keyboard.
- The welcome window turns on Open Shot at login and ShotDev's screenshot shortcuts. Turn Open Shot at login off before shooting Settings, because the old shots show it off.
- On `redesign` and after it merges, ShotDev's windows have a solid background and no longer blur what's behind them. On older builds they're glass, so quit ShotDemo and minimise other windows before shooting them.

## Take assets

computer-use screenshots are for looking only and can't be saved. Make files with `screencapture`:

- **Privacy first.** The screen shows the user's real desktop and terminal even though computer-use screenshots hide them. Ask before minimising their terminal (`osascript` with `AXMinimized`), and bring it back afterwards, then focus it with `activate` as the last step. Never leave it hidden.
- **A window:** list ids with `scripts/winid.py <OwnerName>`, then `screencapture -x -o -l <id> raw.png`.
- **A region** (for the Scroll panel, which is a separate window next to the target): `screencapture -x -R x,y,w,h out.png` in points, with the desktop clear.
- **Match the existing media.** `scripts/compose.py raw.png out.png [width]` puts a window on the grey-purple gradient used by `docs/media`, at 1600×1000 with a shadow.
- Use a scratch save folder, not the user's `~/Pictures/Shot`: `defaults write dev.lorcan.Shot.dev saveFolder <dir>`, and delete the key afterwards. Name the folder `Shot`, because the gallery shows its name.
- The scripts need `python3 -m venv` plus `pip install Pillow pyobjc-framework-Quartz`, which downloads packages, so tell the user first.

## Finish

Quit ShotDemo (or MugCo), stop ShotDev as the `run-shotdev` skill's Stop section says (`StopProject`, then `scripts/dev.sh stop`, which reopens the installed Shot if Run quit it), close any workspace you opened, and refocus the terminal. Each reshot file needs matching alt text next to where the guide uses it.

## Record a clip (GIFs and videos)

- Start `screencapture -v -V <seconds> -R0,38,1920,1205 raw.mov` with `run_in_background`, then run the whole interaction in one `computer_batch` so the timing holds. The recording starts a second or two late, so open with a 3 second wait and trim the start with `ffmpeg -ss`.
- The overlay opens in the mode you used last. Click the Area chip once and press Escape before recording so a drag really drags out an area.
- Click a tool, then wait 1.5 seconds before dragging, or the drag does nothing. Keep arrows inside the image, or the canvas grows and everything shifts.
- `⌘W` on an edited editor asks to save. Click Discard, or stale editor windows show up in the next take.
- Build the site copies with `cd site && npm run media`. Make the GIF from the 2× mp4 at 12 fps and 960 wide: `fps=12,scale=960:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4`.
