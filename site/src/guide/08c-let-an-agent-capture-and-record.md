---
title: Let an agent capture and record
summary: "Let an agent screenshot or record a window, such as the iOS Simulator, to check its own work."
group: AI agents
anchors: [letting-an-agent-capture-and-record]
---

An agent can take its own screenshot or recording of a window, such as the iOS Simulator or the app it's building, so it can check its work without asking you: "record the Simulator while the UI test runs, then show me what happened."

Screen Recording access belongs to Shot, not to your terminal, so the agent asks the running Shot app, through `shot capture`, `shot record`, or the MCP server's `capture_window` and `record_window` tools.

## Turn it on

Turn on **Let agents capture and record** in **Settings › Agents**. It starts off, and it's separate from **Hand captures to agents**. While it's off, Shot refuses every agent request except [asking you to pick](#ask-you-to-pick).

Each time an agent captures or records, Shot shows a notice at the bottom of the screen, such as **An agent took a screenshot of Simulator** or **An agent is recording Simulator**, so you always know.

## Screenshot a window

The agent names the window by a few words of its title or its app, such as `Simulator`, or by its app's bundle ID, such as `com.apple.iphonesimulator`. `shot windows` and the `list_windows` tool list the open windows and the displays to pick from.

```sh
shot capture --window "Simulator"
```

Shot captures that window live, even when other windows cover it, and never brings it forward or takes focus. The agent can also:

- take a whole display,
- keep only part of a window or display (a `rect` in points from its top-left corner),
- leave out the window's shadow,
- wait up to 30 seconds for an animation to finish first.

The screenshot is saved to your capture folder, with a record inside it of which app and window it came from. Nothing else happens: no sound, no copy, no Quick Access card, no editor.

## Record a window as it runs

```sh
shot record --window "Simulator" --duration 10
```

An agent's recording:

- leaves out the microphone and the camera. System audio follows **Settings › Recording**.
- always shows the region border and the recording controls, whatever **Settings › Recording** says, so you can pause, stop or discard it.
- stops itself after 10 minutes.
- is saved to your capture folder without being copied, and without a Quick Access card or confetti.

An agent can only stop its own recordings, never one you started. A recording of part of a window records that part of the screen, so a window in front of it shows too.

## Record while a command runs

```sh
shot record --window Simulator -- xcodebuild test …
```

This records only while the command after `--` runs, so a failed run can't leave the recording going. The command's input and output pass straight through, and <kbd>⌃C</kbd> reaches the command; the recording stops once it exits.

When the command exits, `shot` prints the recording with the command's `exitCode`, and exits with that code, so `&&` chains still work. If the command succeeds but the recording isn't saved, `shot` exits with the recording's error code instead. If the command can't start, `shot` exits with 127 when it isn't found, or 126 otherwise, as a shell does.

## Mark a moment

While its recording runs, an agent can mark a moment with `shot record --mark "tapped Login"` or `record_window`'s `mark` action. The key frames from `get_frames` and `record_window` then include the frame at each mark, with its label.

Marks are kept by Shot, in `~/Library/Application Support/dev.lorcan.Shot/`, not inside the video, so a recording you share doesn't carry them. Moving or renaming the recording loses them.

## Ask you to pick

An agent can also ask **you** to pick what it should see, with `shot pick --prompt "Select the broken toolbar"` or the `ask_for_capture` tool.

1. Shot opens its usual area selection, with the agent's prompt and name above the hint, such as **Claude Code asks: Select the broken toolbar**.
2. Drag across the area, or press <kbd>Space</kbd> and click a window.
3. Shot saves the screenshot to the capture folder, as it does an agent's own, and hands it back to the agent.

<kbd>Esc</kbd> cancels, and the selection closes by itself if you don't pick within the timeout, 60 seconds by default. Since you make the selection, this works with **Let agents capture and record** off.

## Privacy and safety

- Shot notes who asked for each screenshot, recording or edit an agent makes: the `shot` command or the MCP server, the command or tool, and the agent's name as it gives it to the MCP server. Like layers, this is kept in Shot's Application Support folder, never in the file, so a capture you share doesn't say an agent made it.
- If Shot isn't running, `shot capture` opens it in the background first.
- Shot only answers requests from your own user account, over a socket in `~/Library/Application Support/dev.lorcan.Shot/`.
