# Recording

Read this before changing screen recording, pausing or audio.

- `Recorder` uses `SCStream` + `SCRecordingOutput`.
- Each pause starts a new segment, and `VideoConcatenator` joins them on stop.
- With both the microphone and system audio on, each is also written to its own file, so mute silences only the microphone.
- The clock, mute stretches and segment lists live in ShotCore (`RecordingTimeline`, `RecordingSegments`), so `Recorder` only drives SCK and the panels.
- The camera bubble shows, and the recording starts, only once `CameraWarmUp` has seen the camera's first frames with its exposure settled (or 1.5 s pass), so a recording never opens on black frames.
- `Recorder.Options` holds this recording's choices: camera, microphone, cursor, Mac sound and frame rate. They start from Settings, and the check-before-recording bar can change them. While that bar shows the microphone on, `DevicePreview.microphone` runs it for the level meter, and it stops before the recording opens the microphone.
