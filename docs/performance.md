# Performance budgets

Shot is meant to be fast by default. Its worst regressions so far were power features leaking cost into the fast path or into idle time: #217 (closed windows kept animating, 10–65% CPU), #222 (every video frame redrew every annotation), #226, #228, #229, #230 and #231. Each path below has a budget and a check, so these regressions can't come back unnoticed.

## In CI: `make perf`

`Tests/ShotCoreAppleTests/PerfTests.swift` times the pure paths with `ContinuousClock`. After one warm-up run, it keeps the fastest of at least 15 runs spread over at least half a second. A busy runner can only add time, so the fastest run is the closest to what the work costs, and a slow spell would have to last the whole half second to fail a test. `make test` skips the suite. `make perf` and CI's **Perf** step run it alone, one test at a time, so other tests don't skew the timings. CI runs it at the release gate, on the release pull request only, so a regression shows up per release. Run `make perf` yourself when you change `Sources/ShotCore` or `Sources/ShotModel`.

Each budget is 2× the baseline measured on the CI runner, which is slower than the reference Mac. The baseline is the slowest of three CI runs. That leaves room for a noisy runner but still fails a change that does the work again on every call: removing the overlay cache from #222 makes the overlay test about 140× slower.

| Path | What's measured | Reference Mac | CI runner | Budget |
|---|---|---|---|---|
| Flatten + encode | Flatten a 5120×2880 capture with 20 annotations, including a blur and a spotlight, and encode it as PNG | 261 ms | 423 ms | 847 ms |
| Overlay render | `AnnotationFrame.apply` of 20 annotations at 1920×1080, per frame over 30 frames, with the compositor's overlay cache | 9.7 µs | 19.4 µs | 39 µs |
| Marker render | `AnnotationFrame.apply` of one marker over a 1920×1080 frame, which draws the whole canvas on the CPU and sends it back, then reading the frame out | not measured | 14.3 ms | 29 ms |
| GIF export memory | Peak growth of the process footprint while exporting a 20 s 1080p video as a GIF | < 1 MB | 226 MB | 452 MB |
| Gallery grouping | Filter, sort and group 1,500 items into date sections | 1.2 ms | 2.9 ms | 5.8 ms |
| Gallery text search | Search 1,500 items whose screenshots have about 1.5 KB of text each for a word 15 of them contain, then group them | 2.9 ms | not measured yet | 14 ms |

GIF export grows memory by under 1 MB on the reference Mac but by about 226 MB on the CI runner, probably because the runner's virtual machine decodes video in software, inside the test process. The budget follows the CI runner. Reverting #230 adds about 500 MB at this size, as measured in its PR, so CI still catches it.

Gallery text search has no CI baseline yet. Its budget assumes the runner is as much slower as it is for grouping (about 2.4×), then doubles that. Measure it at the next release gate.

To change a budget, measure again, then update both this table and `Budget` in `PerfTests.swift`.

## On Linux: the image effects, the compositor and the writer

Linux has no Core Image, so blur, pixelate and the masks run in plain Swift (`Sources/ShotModel/Bitmap+Effects.swift`), a project's frames are drawn through Cairo by `PortableCompositor`, and `FFmpegWriter` pipes them to ffmpeg. `Tests/ShotCoreLinuxTests/PerfTests.swift` times a blur of a 2560×1600 capture at radius 20, the spotlight blur's default at that size, one 1920×1080 frame, and writing 10 seconds of 1920×1080 video, which it runs once. They run with the other Linux tests in CI's `test` job on every pull request, in a debug build, so each keeps the fastest of only three runs. A budget is 2× the CI runner's time, as on the Mac.

| Path | What's measured | Docker on the reference Mac (debug) | Release build | CI runner (debug) | Budget |
|---|---|---|---|---|---|
| Blur | `PortableEffects.blurred` of an opaque 2560×1600 capture, radius 20 | 650 ms | 100 ms | 1,250 ms | 2,500 ms |
| Compose | `PortableCompositor.frame` of a 1920×1080 frame: a 1280×720 clip turned, with rounded corners, a border and a shadow, over a recording, under an arrow, a box with a shadow and a highlight. Its shadow masks are cached, as from one frame to the next | 140 ms | not measured | 311 ms | 650 ms |
| Write | `FFmpegWriter.write` of a 10 s, 30 fps, 1920×1080 recording with an arrow over 4 s of it: 300 frames decoded, drawn and encoded as H.264 | 13.2 s (ffmpeg 6.1), 16.9 s (4.4) | not measured | measured on this PR's first run | 60 s |

## Locally: `make perf-app`

`scripts/perf.sh` drives an installed Shot (`/Applications/ShotDev.app` by default, or a path you pass) through its URL scheme. CI can't run it, because its runners can't grant the Screen Recording permission. Run it before each release, after `make app`.

The app emits `OSSignposter` signposts under its bundle identifier, in category `perf`, which the script reads with `log show --signpost`. Instruments shows them too.

- **Ready** marks when hotkeys are registered at launch. Its message gives the time since the process started.
- **Capture to clipboard** runs from a full-screen capture action to the clipboard write. Area and window captures have no interval, since they wait for your selection. It ends with `copied`, or `not copied` when nothing was copied.
- **Gallery selection** runs from a click on a gallery tile, or an arrow key, to the Core Animation commit that shows the new selection. Its end message gives the number of items in view, as `items=1500`.
- **Gallery filter** runs the same way from a change to the search text, the filter or the sort to the commit that shows the new grid.

Both gallery intervals end at a commit, which waits for the display's next refresh, so they include up to a frame of waiting as well as the work. A key press that changes nothing still measures about 4 ms. Selection costs the same with 15 items as with 1,500.

The script:

1. Quits any running copy of the app it measures (an installed release keeps running), then launches the app three times and takes the median **launch → ready** time.
2. Takes 20 full-screen captures and reports the median **capture → clipboard** time.
3. Waits for the Quick Access cards to close, then reads the **memory footprint**.
4. Points the save folder at a library of 1,500 seeded screenshots spread over 300 days, opens the gallery, and presses → 30 times and ↓ 15 times, then types a search one letter at a time and deletes it. It reports the median **gallery selection** and **gallery filter** times, then puts the save folder back.
5. Opens and closes the editor, the video editor (with a clip made by `ffmpeg`, if it's installed) and the gallery. It then averages **idle CPU** over 30 seconds.
6. Moves this run's captures out of your capture folder and prints where they went.

It needs Screen Recording for Shot, **Copy to clipboard** turned on in **Settings › Capture**, and Accessibility for the terminal, which presses keys in the gallery and closes Shot's windows with ⌘W. It exits non-zero if a metric is over budget or couldn't be measured.

| Metric | Reference Mac | Budget |
|---|---|---|
| Launch → ready | 101 ms | 150 ms |
| Capture → clipboard (full screen, 3840×2486 px: the 15″ panel at a scaled resolution) | 189 ms | 285 ms |
| Memory after 20 captures | 20 MB | 30 MB |
| Idle CPU, no windows open | 0.0% | at most 1% |
| Gallery selection (1,500 items) | 20 ms | 30 ms |
| Gallery filter (1,500 items) | 24 ms | 36 ms |

Idle CPU has an absolute budget. The others are about 1.5× the baseline, set in `scripts/perf.sh`; change both together.

Memory after 20 captures was 577 MB before #276: macOS kept each capture's freed screen-sized buffers resident for minutes. Shot now turns off malloc's large-block cache and copies PNG only (#278).

## Reference Mac

MacBook Air (Mac16,13), Apple M4, 16 GB, macOS 27.0.1, built-in display only. The `make perf` baselines come from debug builds, as `swift test` makes them. The `make perf-app` baselines come from the build `make app` installs.
