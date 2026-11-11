# Performance budgets

Shot is meant to be fast by default. Its worst regressions so far were power features leaking cost into the fast path or into idle time: #217 (closed windows kept animating, 10–65% CPU), #222 (every video frame redrew every annotation), #226, #228, #229, #230 and #231. Each path below has a budget and a check, so these regressions can't come back unnoticed.

## Locally: `make perf-app`

`scripts/perf.sh` drives a built Shot (`build/ShotDev.app` by default, or a path you pass) through its URL scheme, after quitting every other ShotDev and the installed Shot, which it reopens at the end. CI can't run it, because its runners can't grant the Screen Recording permission. Run it before each release with `make perf-app`, which archives `build/ShotDev.app` first.

The app emits `OSSignposter` signposts under its bundle identifier, in category `perf`, which the script reads with `log show --signpost`. Instruments shows them too.

- **Ready** marks when hotkeys are registered at launch. Its message gives the time since the process started.
- **Capture to clipboard** runs from a full-screen capture action to the clipboard write. Area and window captures have no interval, since they wait for your selection. It ends with `copied`, or `not copied` when nothing was copied.
- **Gallery selection** runs from a click on a gallery tile, or an arrow key, to the Core Animation commit that shows the new selection. Its end message gives the number of items in view, as `items=1500`.
- **Gallery filter** runs the same way from a change to the search text, the filter or the sort to the commit that shows the new grid.
- **Quick Access open** runs from a new card being added to the commit that first shows it, before its slide-in finishes.
- **Window open** runs from the request to open Settings, the gallery, the editor or the video editor to the commit that first shows the window. Its end message names the window, as `settings`. The editor's interval includes reading the image, and the video editor's includes loading the video.
- **Menu shown** is an event, not an interval: it marks the menu bar menu's first pass of tracking, after macOS has built and drawn it. A click on the menu bar icon never reaches the app, so the script times the menu from the moment it posts its own click to this event.

Both gallery intervals end at a commit, which waits for the display's next refresh, so they include up to a frame of waiting as well as the work. A key press that changes nothing still measures about 4 ms. Selection costs the same with 15 items as with 1,500.

The script:

1. Quits any running copy of the app it measures (an installed release keeps running), then launches the app three times and takes the median **launch → ready** time.
2. Takes 20 full-screen captures and reports the median **capture → clipboard** time.
3. Waits for the Quick Access cards to close, then reads the **memory footprint**.
4. Points the save folder at a library of 1,500 seeded screenshots spread over 300 days, opens the gallery, and presses → 30 times and ↓ 15 times, then types a search one letter at a time and deletes it. It reports the median **gallery selection** and **gallery filter** times, then puts the save folder back.
5. Clicks Shot's menu bar icon five times with real mouse events, closing the menu with Escape each time, and reports the median **menu open** time.
6. Opens and closes Settings, the gallery, the editor and the video editor three times each, and reports the median **window open** time of each. The video editor gets a clip made by `ffmpeg`, or `docs/media/recording.mp4` when `ffmpeg` isn't installed.
7. Opens and closes the editor, the video editor and the gallery once more, then averages **idle CPU** over 30 seconds.
8. Moves this run's captures out of your capture folder and prints where they went.

It needs Screen Recording for Shot, **Copy to clipboard** turned on in **Settings › Capture**, and Accessibility for the terminal, which clicks the menu bar icon, presses keys in the gallery and closes Shot's windows with ⌘W. Leave the mouse alone while it runs. It exits non-zero if a metric is over budget or couldn't be measured.

| Metric | Reference Mac | Budget |
|---|---|---|
| Launch → ready | 101 ms | 150 ms |
| Capture → clipboard (full screen, 3840×2486 px: the 15″ panel at a scaled resolution) | 189 ms | 285 ms |
| Memory after 20 captures | 20 MB | 30 MB |
| Idle CPU, no windows open | 0.0% | at most 1% |
| Gallery selection (1,500 items) | 20 ms | 30 ms |
| Gallery filter (1,500 items) | 24 ms | 36 ms |
| Quick Access open | 9 ms | 14 ms |
| Menu open (click to drawn) | 41 ms | 62 ms |
| Settings open | 75 ms | 113 ms |
| Gallery open | 107 ms | 160 ms |
| Editor open (a full-screen capture) | 216 ms | 324 ms |
| Video editor open (a 3-second 720p clip) | 66 ms | 99 ms |

Idle CPU has an absolute budget. The others are about 1.5× the baseline, set in `scripts/perf.sh`; change both together.

Memory after 20 captures was 577 MB before #276: macOS kept each capture's freed screen-sized buffers resident for minutes. Shot now turns off malloc's large-block cache and copies PNG only (#278).

## Reference Mac

MacBook Air (Mac16,13), Apple M4, 16 GB, macOS 27.0.1, built-in display only. The `make perf-app` baselines come from the Release build `make bundle` archives.

## The redesign compared with `main`

#1122 measured the redesign against `main` on the reference Mac, in November 2026, before it merged. Both were Release builds with the same signposts, and each figure is the median of three alternating runs.

| Metric | `main` | `redesign` |
|---|---|---|
| Launch → ready | 128 ms | 112 ms |
| Capture → clipboard | 235 ms | 227 ms |
| Memory after 20 captures | 18 MB | 19 MB |
| Idle CPU | 0.0% | 0.0% |
| Quick Access open | 9 ms | 9 ms |
| Menu open | 47 ms | 50 ms |
| Settings open | 91 ms | 82 ms |
| Gallery open | 118 ms | 105 ms |
| Editor open | 231 ms | 231 ms |
| Video editor open | 90 ms | 76 ms |
| Gallery selection (1,500 items) | 15 ms | 20 ms |
| Gallery filter (1,500 items) | 12 ms | 10 ms |

Three paths came out behind. The gallery's selection bar rebuilt its buttons, tips and Move to menu on every arrow key, so it now takes a summary of the selection that stays the same while one selected item moves (`Gallery.SelectionSummary`), and its actions read the selection when clicked. The menu made each row's icon again on every open, so the icons are now cached, and a run after that measured it at 41 ms. The extra megabyte is the menu's Recent row, which keeps four small thumbnails.
