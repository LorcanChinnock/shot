# Recording

Read this before changing screen recording, pausing or audio.

- `Recorder` uses `SCStream` + `SCRecordingOutput`.
- Each pause starts a new segment, and `VideoConcatenator` joins them on stop.
- With both the microphone and system audio on, each is also written to its own file, so mute silences only the microphone.
