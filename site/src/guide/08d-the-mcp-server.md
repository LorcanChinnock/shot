---
title: The MCP server
summary: "Connect Claude, Claude Code, Cursor or another assistant to Shot, so it can read, edit and take captures itself."
group: AI agents
---

Shot comes with a small [MCP](https://modelcontextprotocol.io) server, so you can ask an agent "what did I mark in my latest screenshot?" without pasting anything.

## Add it to your agent

1. Open **Settings › Agents**. The **MCP server** card lists each assistant and agent it finds on your Mac, plus a setup any other app can use. If it finds none, it lists them all.
2. Click **Install** beside yours. The row then shows **Installed**. If it shows **Update**, the setup points at a copy of Shot that has moved, so click it to fix that.
3. Restart the app if Shot asks you to. Claude only reads its setup when it opens.

How Install adds Shot depends on the app:

| App | What Install does |
|---|---|
| Claude, Windsurf | Adds Shot to the app's config file, after saving a copy of the file beside it with `.bak` on the end. If the file isn't valid JSON, Shot leaves it alone. |
| LM Studio, Raycast, Cursor, VS Code | Opens the app, which asks you to confirm. |
| Claude Code, Codex, Gemini CLI | Runs the agent's own command, such as `claude mcp add`. If Shot can't find the command, copy it and run it in Terminal. |
| Zed, any other app | Only **Copy**. Paste the setup into the app's settings. |

> [!NOTE]
> ChatGPT isn't on the list. It only connects to MCP servers on the internet, and Shot's runs on your Mac. You can still paste screenshots into it.

Or set it up by hand:

- **Claude Code:** `claude mcp add -s user shot -- /Applications/Shot.app/Contents/MacOS/shot-cli mcp`. Without `-s user`, Claude Code adds the server only to the folder you run the command in.
- **Claude, Cursor** and other apps that take a JSON config:

  ```json
  { "mcpServers": { "shot": { "command": "/Applications/Shot.app/Contents/MacOS/shot-cli", "args": ["mcp"] } } }
  ```

- **Codex:** `codex mcp add shot -- /Applications/Shot.app/Contents/MacOS/shot-cli mcp`, or in `~/.codex/config.toml`:

  ```toml
  [mcp_servers.shot]
  command = "/Applications/Shot.app/Contents/MacOS/shot-cli"
  args = ["mcp"]
  ```

- **Gemini CLI:** `gemini mcp add -s user shot /Applications/Shot.app/Contents/MacOS/shot-cli mcp`.

## What it needs

- The server runs only while the agent uses it, and works whether Shot is open or not.
- It needs no setting turned on. Without [**Hand captures to agents**](#hand-captures-to-agents), Shot has no record of where a capture came from or what you marked, but the agent still sees the image.
- Only `list_windows`, `capture_window` and `record_window` need [**Let agents capture and record**](#let-an-agent-capture-and-record). They and `ask_for_capture` open Shot in the background if it isn't running.

> [!TIP]
> The first time the server reads `~/Pictures`, macOS may ask whether your terminal or editor can access that folder. Allow it, or the agent sees no captures. To check which copy of Shot and which folder the server uses, and whether the agent can read it, run `/Applications/Shot.app/Contents/MacOS/shot-cli doctor`.

## Tools

The server has eighteen tools:

- seven read your captures, one of them by waiting for your next,
- seven make a new file from them,
- one lists the open windows,
- two take a screenshot or a recording,
- and one asks you to pick what to capture.

Their arguments are optional unless the table says otherwise, and a slightly wrong one is read as best it can be rather than refused.

| Tool | Arguments | Returns |
|---|---|---|
| `latest_capture` | `kind`: `image` (the default), `video` or `any` | The capture you just took: a preview image, its path, when it was taken, and what Shot recorded in it, as a few plain lines: the app and window, your notes, which areas are redacted, and each mark with where it is. A screenshot you saved again from the editor stands in for the original, since that version has your markup. A recording gives a frame from it, how long it runs, and whether it has sound. |
| `list_captures` | `limit`: 1 to 50, 10 by default; `since`: a date such as `2026-10-10`, or a span back from now such as `10m`, `2h` or `3d`; `query`: words to find, ignoring case and accents | Recent captures, newest first: name, path, kind and when. No images. With `query`, only the captures whose name or screenshot text contains it, as the [gallery's search](#search-filter-and-sort) finds them, each with up to three `matchingLines`. It searches the text Shot has already read, and says how many screenshots it hasn't read yet. |
| `get_capture` | `path`, or `name`: a file name or a few words from it, so `shot 14.03` finds `Shot 2026-10-10 at 14.03.12.png` | The same as `latest_capture`, for that capture. If none matches, it names the closest ones. |
| `get_frames` | `path` or `name`, else the newest recording; `count`: 1 to 12, 8 by default | Still frames of the recording, since a model can't watch video: the first and last, the frame after each change on screen once it settles, and the frame at each [mark](#mark-a-moment) with its label, each with its time. When the recording has sound, what's said in it comes too, transcribed on your Mac, each phrase with its times after the frame on screen as it starts. Nothing is written. |
| `find_text` | `path` or `name`, else the newest screenshot; `query`: words to find, ignoring case and accents | The text in the screenshot, read on your Mac: each line with its box, `[x, y, width, height]` in the file's pixels from the top left, the space `annotate` takes. With `query`, only the lines that contain it, each with the box of the matching words, so an agent can check what the screen says or find the button to point at. Nothing is written. |
| `zoom` | `rect` (required): `[x, y, width, height]` in the file's pixels from the top left; `path` or `name`, else the newest screenshot | That part of the screenshot at full resolution, so an agent can read small text that the preview shrinks, such as in a 5K capture. A part longer than 1568 pixels on a side is scaled down to fit, and the result says by how much. A `rect` reaching past the edge is cut to the image. Nothing is written. |
| `wait_for_capture` | `kind`: `image`, `video` or `any` (the default); `timeout`: up to 120 seconds, 60 by default | Waits for your next capture, then returns it as `latest_capture` does, so an agent can ask you to "screenshot the broken toolbar" and carry on once you have. Only a capture taken after the call counts, and a recording counts once Shot has finished writing it. If none comes in time, it says so, and the agent can call again. |
| `ask_for_capture` | `prompt`: what to select, up to 100 characters, such as `Select the broken toolbar`; `timeout`: up to 120 seconds, 60 by default | [Asks you to pick](#ask-you-to-pick) an area, window or display, showing the prompt and the agent's name, then returns the screenshot as `capture_window` does. If you press Esc or don't pick in time, it says so. Works with **Let agents capture and record** off. |
| `annotate` | `annotations` (required): marks in the [record's format](#the-capture-record), except `image`; `path` or `name`, else the newest screenshot | A copy with the marks drawn on, saved as the screenshot's next version, and a preview of it. Open it in Shot and the marks are still live, along with any already on a version you [saved](#reopen-a-saved-version). |
| `redact` | `detect`: a list of `email`, `token` (tokens and API keys) and `card` (card numbers), all three by default, or none when `rects` are given; `rects`: areas to hide as well, each `[x, y, width, height]` in the file's pixels; `style`: `pixelate` (the default) or `blur`; `path` or `name`, else the newest screenshot | A copy with each email, token and card number it reads hidden, saved as the screenshot's next version, and a preview of it, so an agent can hide private text before it reads a capture. Each find comes with its kind and box, never its text. If there's nothing to hide, no file is written. Open the copy in Shot and the hidden areas are layers you can move or remove. |
| `edit_image` | Any of the [edit's fields](#editing-images): `crop`, `pad`, `background`, `style`, `marks`, `remove`, `place`, `scale` and `format`; `path` or `name`, else the newest screenshot. `place` takes other screenshots in the capture folder, by path or a few words of the name. | A copy with every change made, as you'd make it in the editor, saved as the screenshot's next version, and a preview of it, with each layer's `id` and `type` in `layers`. Open it in Shot and the marks, placed screenshots, padding, style and crop are all still live. |
| `edit_video` | Any of the [video edit's fields](#editing-videos): `keep` or `cut`, `speed`, `mute`, `crop`, `marks`, `append`, `format`, `maxBytes`, and a GIF's `fps` and `width`; `path` or `name`, else the newest recording. `append` takes other recordings in the capture folder, by path or a few words of the name. | A new file beside the recording with every change made, as the video editor and its export make them: its `path`, `size`, `bytes` and `duration`, and for a GIF its `frames` and `fps`. **Edit** on it opens the edit in the video editor, still live. |
| `make_gif` | `path` or `name`, else the newest recording; `start`, `end` in seconds; `fps`, 1 to 30, 12 by default; `width`, 720 by default, or 0 for the recording's own | A GIF of the recording, or part of it, saved beside it. GIFs stop at 60 seconds. **Edit** on it opens the trim in the video editor. |
| `trim_video` | `start` and `end` in seconds (required); `path` or `name`, else the newest recording | The part between the two times, saved beside the recording, without re-encoding where it can. It opens in the video editor with the trim still adjustable. |
| `compare` | `a` and `b` (required): the screenshots before and after, each a path or a few words of its name; `threshold`, 0 to 1, 0.1 by default | Where `b` differs from `a`, to check that a fix changed only what it should. The diff image is a dimmed copy of `b` with the changes lit up and boxed, saved beside `b` as `name diff.png`. With it come each changed region as `[x, y, width, height]` in `b`'s pixels and the share of pixels that changed. Screenshots of different sizes are compared at `b`'s size, and the result says so. |
| `list_windows` | None | The open windows, front to back: each one's `app`, `bundleID`, `title`, `size` in points and whether it's `frontmost`, and the `displays`, numbered from 1, with their size and scale |
| `capture_window` | One of `window`, a few words of the window's title or its app, such as `Simulator`, or `bundleID`, for that app's front window (with `window` too, the one of its windows that matches), or `display`, a number from `list_windows`. Also `rect`, as `[x, y, width, height]` in points from the top-left corner, `noShadow`, and `waitStable`, the most seconds to wait for the picture to stop changing, up to 30 | A [screenshot of that window or display](#screenshot-a-window), saved to the capture folder: a preview, its path and size, and which app and window it was. If no window matches, the error lists the open ones. |
| `record_window` | `action`: `start` (the default), `stop` or `mark`. Start takes a `window`, `bundleID` or `display`, and `rect` and `noShadow`, as `capture_window` takes them, and `duration` in seconds, where more than 120 records 120. Mark takes `label` (required). Stop and mark take `id`, else the agent's recording in progress. | A [recording of that window or display](#record-a-window-as-it-runs). With a `duration`, it waits, then gives the recording's path, length and about 6 key frames, as `get_frames` does. Without one, it gives an `id` at once; stopping it gives the path and frames. A mark gives its `time` in the recording, and the frame there joins the key frames. |

## Previews and transcripts

Previews are JPEGs at most 1568 pixels on the long edge and about 1 MB, which is what vision models work at anyway. The key frames from `get_frames` and `record_window` are at most 1024 pixels and 400 KB each, so a dozen fit in one result. The transcript beside them needs macOS 26 and a language with on-device speech recognition. Nothing leaves your Mac, and it asks for no permission, since it reads the saved file rather than the microphone. It hears any speech in the sound, from the microphone or from other apps. The path in the result lets an agent that can read files open the full-size original, and the marks' coordinates are always in the full-size file's pixels.

## What it can and can't touch

The server reads only the capture folder: your save folder (`~/Pictures/Shot` by default), or the temporary folder when **Save to folder** is off. It captures or records a window only when you've turned on **Let agents capture and record**, and then only through the running Shot app. It never moves or deletes anything, and never changes a file: `annotate`, `redact`, `edit_image`, `edit_video`, `make_gif`, `trim_video` and `compare` only add a new file beside the capture they start from. It uploads nothing itself.
