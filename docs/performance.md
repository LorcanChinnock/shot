# Performance budgets

Shot is meant to be fast by default. Its worst regressions so far were power features leaking cost into the fast path or into idle time: #217 (closed windows kept animating, 10–65% CPU), #222 (every video frame redrew every annotation), #226, #228, #229, #230 and #231. Each path below has a budget and a check, so these regressions can't come back unnoticed.

## In CI: `make perf`

`Tests/ShotCoreTests/PerfTests.swift` times the pure paths with `ContinuousClock`, taking the median of five runs after one warm-up run. `make test` skips the suite. `make perf` and CI's **Perf** step run it alone, one test at a time, so other tests don't skew the timings.

Each budget is 2× the baseline measured on the CI runner, which is slower than the reference Mac. That leaves room for a noisy runner but still fails a change that does the work again on every call: removing the overlay cache from #222 makes the overlay test about 140× slower.

| Path | What's measured | Reference Mac | CI runner | Budget |
|---|---|---|---|---|
| Flatten + encode | Flatten a 5120×2880 capture with 20 annotations, including a blur and a spotlight, and encode it as PNG | 272 ms | 430 ms | 860 ms |
| Overlay render | `AnnotationFrame.apply` of 20 annotations at 1920×1080, per frame over 30 frames, with the compositor's overlay cache | 10.8 µs | 18.3 µs | 37 µs |
| GIF export memory | Peak growth of the process footprint while exporting a 20 s 1080p video as a GIF | < 1 MB | 226 MB | 452 MB |
| Gallery grouping | Filter, sort and group 1,500 items into date sections | 1.4 ms | 2.9 ms | 6 ms |

GIF export grows memory by under 1 MB on the reference Mac but by about 226 MB on the CI runner, probably because the runner's virtual machine decodes video in software, inside the test process. The budget follows the CI runner. Reverting #230 adds about 500 MB at this size, as measured in its PR, so CI still catches it.

To change a budget, measure again, then update both this table and `Budget` in `PerfTests.swift`.

## Locally: `make perf-app`

`scripts/perf.sh` drives an installed Shot (`/Applications/Shot.app` by default, or a path you pass) through the `shot://` scheme. CI can't run it, because its runners can't grant the Screen Recording permission. Run it before each release, after `make app`.

The app emits `OSSignposter` signposts under its bundle identifier, in category `perf`, which the script reads with `log show --signpost`. Instruments shows them too.

- **Ready** marks when hotkeys are registered at launch. Its message gives the time since the process started.
- **Capture to clipboard** runs from a full-screen capture action to the clipboard write. Area and window captures have no interval, since they wait for your selection. It ends with `copied`, or `not copied` when nothing was copied.

The script:

1. Quits any running Shot, then launches the app three times and takes the median **launch → ready** time.
2. Takes 20 full-screen captures and reports the median **capture → clipboard** time.
3. Waits for the Quick Access cards to close, then reads the **memory footprint**.
4. Opens and closes the editor, the video editor (with a clip made by `ffmpeg`, if it's installed) and the gallery. It then averages **idle CPU** over 30 seconds.
5. Moves this run's captures out of your capture folder and prints where they went.

It needs Screen Recording for Shot, and Accessibility for the terminal, which closes Shot's windows with ⌘W. It exits non-zero if a metric is over budget or couldn't be measured.

| Metric | Reference Mac | Budget |
|---|---|---|
| Launch → ready | 101 ms | 150 ms |
| Capture → clipboard (full screen, 3840×2486 px: the 15″ panel at a scaled resolution) | 189 ms | 285 ms |
| Memory after 20 captures | 20 MB | 30 MB |
| Idle CPU, no windows open | 0.0% | under 1% |

Idle CPU has an absolute budget. The others are about 1.5× the baseline, set in `scripts/perf.sh`; change both together.

Memory after 20 captures was 577 MB before #276: macOS kept each capture's freed screen-sized buffers resident for minutes. Shot now turns off malloc's large-block cache and copies PNG only (#278).

## Reference Mac

MacBook Air (Mac16,13), Apple M4, 16 GB, macOS 27.0.1, built-in display only. The `make perf` baselines come from debug builds, as `swift test` makes them. The `make perf-app` baselines come from the build `make app` installs.
