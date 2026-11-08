# Recording

Read this before changing screen recording, pausing or audio.

- `Recorder` uses `SCStream` + `SCRecordingOutput`.
- Each pause starts a new segment, and `VideoConcatenator` joins them on stop.
- With both the microphone and system audio on, each is also written to its own file, so mute silences only the microphone.
- The clock, mute stretches and segment lists live in ShotCore (`RecordingTimeline`, `RecordingSegments`), so `Recorder` only drives SCK and the panels.
- The camera bubble shows, and the recording starts, only once `CameraWarmUp` has seen the camera's first frames with its exposure settled (or 1.5 s pass), so a recording never opens on black frames.
- `Recorder.Options` holds this recording's choices: camera, microphone, cursor, Mac sound and frame rate. They start from Settings, and the check-before-recording bar can change them. While that bar shows the microphone on, `DevicePreview.microphone` runs it for the level meter, and it stops before the recording opens the microphone.
- `RecordingSessionModel.seconds` is the timer the controls and the menu bar show. Its clock ticks once on each whole second recorded, from `showPanels` to `hidePanels`, so neither redraws more often. `RecordingClock` in ShotCore formats it. `Recorder.onSecond` passes it to `AppState.recordingSeconds`, and `StatusMenu` then draws `BrandMark.timerImage` in place of the mark.
- The border (`RecordingBorderPanel`) sits outside the recorded area and is left out of the video like Shot's other windows. Shape layers draw it, so a large area costs no bitmap.
- With Show clicks on, `ClickRings` draws Shot's own ring for each click inside the area, in one small panel that the filter lets in, so the ring is in the video. Event monitors catch the clicks, which needs no permission, and a click while paused gets no ring. `makeFilter` fetches the shareable content again until it lists that panel, since the window server can take a moment to list a window just ordered in. A window recording captures only its window, so there SCK's `showMouseClicks` draws the clicks instead. `RecordingBorder` and `ClickRing` in ShotCore hold the sizes and timing, with tests.
