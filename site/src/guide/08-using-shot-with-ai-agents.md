---
title: Using Shot with AI agents
summary: "Hand your captures to Claude Code, Codex or Cursor, and let them capture and record for you."
group: AI agents
---

Claude Code, Codex and Cursor all take a pasted screenshot, and your arrows and boxes show the agent where to look. Shot can also hand over the file itself, say exactly what you marked, and let the agent fetch your latest capture on its own.

![Settings › Agents with Hand captures to agents and Let agents capture and record turned on, the shot command installed, and the MCP setup commands for Claude Code, Cursor and Codex, each with a Copy button](../../../docs/media/agents-settings.png)

- **Copy the path.** Right-click a Quick Access card and choose **Copy Path**, or give **Copy Latest Capture's Path** a shortcut in **Settings › Shortcuts**. An agent can open the file from its path, now or later in the conversation, and find what Shot recorded in it. Copies are always the image alone.
- **Turn on Hand captures to agents** in **Settings › Agents** to record, inside each screenshot you take or save from the editor, which app and window it came from and what you marked. Agents read it through the [MCP server](#the-mcp-server). A copied capture is also kept as a file, even with **Save to folder** off, so the agent can fetch it. With saving off, that file stays in a temporary folder for about a day: Shot deletes older ones when it launches. With the setting off, Shot records nothing.

The record is stored in the image's own metadata, as JSON in the XMP property `shot:record` (namespace `https://shot.lorcanchinnock.com/ns/capture/1.0/`), so there's no extra file in your capture folder and it goes wherever the file goes. A copy of a PNG capture keeps it too, but a copy of a JPEG capture or of a styled capture doesn't, since those are new PNGs. Window titles can be private, which is one reason it's opt-in. Recordings have no record. It follows the `shot.capture/2` schema:

```json
{
  "schema": "shot.capture/2",
  "original": "Shot 2026-10-10 at 14.03.12.png",
  "kind": "image",
  "created": "2026-10-10T14:03:12Z",
  "size": { "width": 2880, "height": 1800 },
  "scale": 2,
  "source": {
    "mode": "window",
    "app": "Simulator", "bundleID": "com.apple.iphonesimulator",
    "windowTitle": "iPhone 17 Pro",
    "screenFrame": { "x": 120, "y": 80, "width": 1440, "height": 900 }
  },
  "canvas": [0, 0, 2880, 1800],
  "coordinateSpace": "image pixels, top-left origin",
  "annotations": [
    { "id": "…", "type": "arrow", "from": [410, 220], "to": [612, 388], "color": "red", "hex": "#FF3B30", "lineWidth": 4 },
    { "id": "…", "type": "rectangle", "rect": [560, 340, 220, 96], "color": "red", "hex": "#FF3B30", "lineWidth": 4 },
    { "id": "…", "type": "text", "text": "too tight here", "rect": [600, 450, 180, 32], "color": "red", "hex": "#FF3B30", "fontSize": 24 },
    { "id": "…", "type": "counter", "number": 1, "center": [300, 120], "color": "red", "hex": "#FF3B30", "lineWidth": 4 },
    { "id": "…", "type": "blur", "rect": [40, 40, 300, 30], "note": "redacted, content hidden", "amount": 0.008 }
  ]
}
```

- `original` is set on a version saved from the editor, and names the file it was saved from, in the same folder. `canvas` is the part of that file the version shows, in its pixels: a crop, or past its edges where you added padding. `crop` is there when the version is a crop of it, in the same pixels, and Shot reopens the version with that crop still adjustable. `editable` is `true` when the marks rebuild every layer exactly, and Shot then reopens the version as `original` with the marks live.
- `source.mode` is `area`, `window` or `fullscreen`. A window capture names the app and its window; an area or full screen capture names the frontmost app. `screenFrame` is in points, with the origin at the top left of the main display.
- Coordinates are pixels of the saved file, from its top left, so a crop or padding and **Scale Retina captures to 1×** are already applied. `rect` is `[x, y, width, height]`; `from`, `to` and `center` are `[x, y]`; a pen or marker stroke's `points` are `[[x, y], …]`.
- `type` is one of `arrow`, `line`, `rectangle`, `ellipse`, `triangle`, `diamond`, `star`, `highlight`, `text`, `note`, `counter`, `pen`, `marker`, `image`, `blur`, `pixelate` or `spotlight`; an agent that writes marks can still give `rounded`, which means a `rectangle` with the default `cornerRadius`. `color` is the nearest palette name, with the exact `hex` beside it. Text and notes give their `text`; a blur, pixelate, spotlight or placed image gives only where it is, never what's under it. Hidden layers are left out.
- `lineWidth`, `fill`, `fontSize`, `amount` (a blur's or pixelation's strength), `bend` and `cornerRadius` (a shape's rounded corners) are there so Shot can rebuild a mark; an agent can ignore them.
- `id` names the layer, and an [edit's](#editing-images) `remove` takes it. Marks an agent writes can leave it out.

Development builds before 0.7.0-beta.40 wrote this as a `.shot.json` file beside each capture instead. Nothing reads those any more, so you can delete them.

## Letting an agent capture and record

An agent can take its own screenshot or recording of a window, such as the iOS Simulator or the app it's building, so it can check its work without asking you: "record the Simulator while the UI test runs, then show me what happened." Screen Recording access belongs to Shot, not to your terminal, so the agent asks the running Shot app through `shot capture`, `shot record`, or the MCP server's `capture_window` and `record_window` tools.

- **Turn on Let agents capture and record** in **Settings › Agents**. It's off by default and separate from **Hand captures to agents**. While it's off, Shot refuses every agent request except a pick, below.
- The agent names the window by a few words of its title or its app, such as `Simulator`, or by its app's bundle ID, such as `com.apple.iphonesimulator`. Shot captures that window live, even when other windows cover it, and never brings it forward or takes focus. `shot windows` and the `list_windows` tool list the open windows and the displays to pick from.
- It can also take a whole display, keep only part of a window or display (a `rect` in points from its top-left corner), leave out the window's shadow, or wait for an animation to finish before the screenshot, for up to 30 seconds. A recording of part of a window records that part of the screen, so a window in front of it shows too.
- The screenshot is saved to your capture folder, with a record inside it of which app and window it came from. Nothing else happens: no sound, no copy, no Quick Access card, no editor.
- An agent's recording leaves out the microphone and the camera. System audio follows **Settings › Recording**. It always shows the region border and the recording controls, whatever **Settings › Recording** says, so you can pause, stop or discard it. It stops itself after 10 minutes. It's saved to your capture folder without being copied to the clipboard, and without a Quick Access card or confetti. An agent can only stop its own recordings, never one you started.
- Shot notes who asked for each screenshot, recording or edit an agent makes: the `shot` command or the MCP server, the command or tool, and the agent's name as it gives it to the MCP server. Like layers, this is kept in Shot's Application Support folder, never in the file, so a capture you share doesn't say an agent made it.
- `shot record --window Simulator -- xcodebuild test …` records only while the command after `--` runs, so a failed run can't leave the recording going. The command's input and output pass straight through. When it exits, the recording stops, and `shot` prints it with the command's `exitCode` and exits with that code, so `&&` chains still work. If the command succeeds but the recording isn't saved, `shot` exits with the recording's error code instead. If the command can't start, `shot` exits with 127 when it isn't found, or 126 otherwise, as a shell does. Ctrl-C reaches the command, and the recording stops once the command exits.
- While its recording runs, an agent can mark a moment with `shot record --mark "tapped Login"` or `record_window`'s `mark` action. The key frames from `get_frames` and `record_window` then include the frame at each mark, with its label. Marks are kept by Shot, in `~/Library/Application Support/dev.lorcan.Shot/`, not inside the video, so a recording you share doesn't carry them. Moving or renaming the recording loses them.
- An agent can also ask **you** to pick what it should see, with `shot pick --prompt "Select the broken toolbar"` or the `ask_for_capture` tool. Shot opens its usual area selection with the agent's prompt and name above the hint, such as **Claude Code asks: Select the broken toolbar**. Space switches to picking a window, as it always does. What you pick is saved to the capture folder, as an agent's own screenshot is, and handed back to the agent. Esc cancels, and the selection closes by itself if you don't pick within the timeout, 60 seconds by default. Since you make the selection, this works with **Let agents capture and record** off.
- Each time, Shot shows a notice at the bottom of the screen, such as **An agent took a screenshot of Simulator** or **An agent is recording Simulator**, so you always know.
- If Shot isn't running, `shot capture` opens it in the background first. Shot only answers requests from your own user account, over a socket in `~/Library/Application Support/dev.lorcan.Shot/`.

## The MCP server

Shot also comes with a small [MCP](https://modelcontextprotocol.io) server, so you can ask an agent "what did I mark in my latest screenshot?" without pasting anything. It runs only while the agent uses it, works whether or not Shot is open, and needs no setting turned on, though without **Hand captures to agents** Shot has no record of where a capture came from or what you marked; the agent still sees the image. Only `list_windows`, `capture_window` and `record_window` need [**Let agents capture and record**](#letting-an-agent-capture-and-record) on. They and `ask_for_capture` open Shot in the background if it isn't running. **Settings › Agents** shows the setup commands with the right path for your copy of Shot, for the agents it finds on your Mac (Claude Code, Cursor or Codex), plus a JSON config any other app can use. If it finds none, it shows them all.

- **Claude Code:** `claude mcp add -s user shot -- /Applications/Shot.app/Contents/MacOS/shot-cli mcp`. Without `-s user`, Claude Code adds the server only to the folder you run the command in.
- **Cursor** and other apps that take a JSON config:

  ```json
  { "mcpServers": { "shot": { "command": "/Applications/Shot.app/Contents/MacOS/shot-cli", "args": ["mcp"] } } }
  ```

- **Codex**, in `~/.codex/config.toml`:

  ```toml
  [mcp_servers.shot]
  command = "/Applications/Shot.app/Contents/MacOS/shot-cli"
  args = ["mcp"]
  ```

It has eighteen tools. Seven read your captures, one of them by waiting for your next, seven make a new file from them, one lists the open windows, two take a screenshot or a recording, and one asks you to pick what to capture. Their arguments are optional unless the table says otherwise, and a slightly wrong one is read as best it can be rather than refused.

| Tool | Arguments | Returns |
|---|---|---|
| `latest_capture` | `kind`: `image` (the default), `video` or `any` | The capture you just took: a preview image, its path, when it was taken, and what Shot recorded in it, as a few plain lines: the app and window, your notes, which areas are redacted, and each mark with where it is. A screenshot you saved again from the editor stands in for the original, since that version has your markup. A recording gives a frame from it, how long it runs, and whether it has sound. |
| `list_captures` | `limit`: 1 to 50, 10 by default; `since`: a date such as `2026-10-10`, or a span back from now such as `10m`, `2h` or `3d`; `query`: words to find, ignoring case and accents | Recent captures, newest first: name, path, kind and when. No images. With `query`, only the captures whose name or screenshot text contains it, as the [gallery's search](#gallery) finds them, each with up to three `matchingLines`. It searches the text Shot has already read, and says how many screenshots it hasn't read yet. |
| `get_capture` | `path`, or `name`: a file name or a few words from it, so `shot 14.03` finds `Shot 2026-10-10 at 14.03.12.png` | The same as `latest_capture`, for that capture. If none matches, it names the closest ones. |
| `get_frames` | `path` or `name`, else the newest recording; `count`: 1 to 12, 8 by default | Still frames of the recording, since a model can't watch video: the first and last, the frame after each change on screen once it settles, and the frame at each [mark](#letting-an-agent-capture-and-record) with its label, each with its time. When the recording has sound, what's said in it comes too, transcribed on your Mac, each phrase with its times after the frame on screen as it starts. Nothing is written. |
| `find_text` | `path` or `name`, else the newest screenshot; `query`: words to find, ignoring case and accents | The text in the screenshot, read on your Mac: each line with its box, `[x, y, width, height]` in the file's pixels from the top left, the space `annotate` takes. With `query`, only the lines that contain it, each with the box of the matching words, so an agent can check what the screen says or find the button to point at. Nothing is written. |
| `zoom` | `rect` (required): `[x, y, width, height]` in the file's pixels from the top left; `path` or `name`, else the newest screenshot | That part of the screenshot at full resolution, so an agent can read small text that the preview shrinks, such as in a 5K capture. A part longer than 1568 pixels on a side is scaled down to fit, and the result says by how much. A `rect` reaching past the edge is cut to the image. Nothing is written. |
| `wait_for_capture` | `kind`: `image`, `video` or `any` (the default); `timeout`: up to 120 seconds, 60 by default | Waits for your next capture, then returns it as `latest_capture` does, so an agent can ask you to "screenshot the broken toolbar" and carry on once you have. Only a capture taken after the call counts, and a recording counts once Shot has finished writing it. If none comes in time, it says so, and the agent can call again. |
| `ask_for_capture` | `prompt`: what to select, up to 100 characters, such as `Select the broken toolbar`; `timeout`: up to 120 seconds, 60 by default | [Asks you to pick](#letting-an-agent-capture-and-record) an area, window or display, showing the prompt and the agent's name, then returns the screenshot as `capture_window` does. If you press Esc or don't pick in time, it says so. Works with **Let agents capture and record** off. |
| `annotate` | `annotations` (required): marks in the [record's format](#using-shot-with-ai-agents), except `image`; `path` or `name`, else the newest screenshot | A copy with the marks drawn on, saved as the screenshot's next version, and a preview of it. Open it in Shot and the marks are still live, along with any already on a version you [saved](#reopen-a-saved-version). |
| `redact` | `detect`: a list of `email`, `token` (tokens and API keys) and `card` (card numbers), all three by default, or none when `rects` are given; `rects`: areas to hide as well, each `[x, y, width, height]` in the file's pixels; `style`: `pixelate` (the default) or `blur`; `path` or `name`, else the newest screenshot | A copy with each email, token and card number it reads hidden, saved as the screenshot's next version, and a preview of it, so an agent can hide private text before it reads a capture. Each find comes with its kind and box, never its text. If there's nothing to hide, no file is written. Open the copy in Shot and the hidden areas are layers you can move or remove. |
| `edit_image` | Any of the [edit's fields](#editing-images): `crop`, `pad`, `background`, `style`, `marks`, `remove`, `place`, `scale` and `format`; `path` or `name`, else the newest screenshot. `place` takes other screenshots in the capture folder, by path or a few words of the name. | A copy with every change made, as you'd make it in the editor, saved as the screenshot's next version, and a preview of it, with each layer's `id` and `type` in `layers`. Open it in Shot and the marks, placed screenshots, padding, style and crop are all still live. |
| `edit_video` | Any of the [video edit's fields](#editing-videos): `keep` or `cut`, `speed`, `mute`, `crop`, `marks`, `append`, `format`, `maxBytes`, and a GIF's `fps` and `width`; `path` or `name`, else the newest recording. `append` takes other recordings in the capture folder, by path or a few words of the name. | A new file beside the recording with every change made, as the video editor and its export make them: its `path`, `size`, `bytes` and `duration`, and for a GIF its `frames` and `fps`. **Edit** on it opens the edit in the video editor, still live. |
| `make_gif` | `path` or `name`, else the newest recording; `start`, `end` in seconds; `fps`, 1 to 30, 12 by default; `width`, 720 by default, or 0 for the recording's own | A GIF of the recording, or part of it, saved beside it. GIFs stop at 60 seconds. **Edit** on it opens the trim in the video editor. |
| `trim_video` | `start` and `end` in seconds (required); `path` or `name`, else the newest recording | The part between the two times, saved beside the recording, without re-encoding where it can. It opens in the video editor with the trim still adjustable. |
| `compare` | `a` and `b` (required): the screenshots before and after, each a path or a few words of its name; `threshold`, 0 to 1, 0.1 by default | Where `b` differs from `a`, to check that a fix changed only what it should. The diff image is a dimmed copy of `b` with the changes lit up and boxed, saved beside `b` as `name diff.png`. With it come each changed region as `[x, y, width, height]` in `b`'s pixels and the share of pixels that changed. Screenshots of different sizes are compared at `b`'s size, and the result says so. |
| `list_windows` | None | The open windows, front to back: each one's `app`, `bundleID`, `title`, `size` in points and whether it's `frontmost`, and the `displays`, numbered from 1, with their size and scale |
| `capture_window` | One of `window`, a few words of the window's title or its app, such as `Simulator`, or `bundleID`, for that app's front window (with `window` too, the one of its windows that matches), or `display`, a number from `list_windows`. Also `rect`, as `[x, y, width, height]` in points from the top-left corner, `noShadow`, and `waitStable`, the most seconds to wait for the picture to stop changing, up to 30 | A [screenshot of that window or display](#letting-an-agent-capture-and-record), saved to the capture folder: a preview, its path and size, and which app and window it was. If no window matches, the error lists the open ones. |
| `record_window` | `action`: `start` (the default), `stop` or `mark`. Start takes a `window`, `bundleID` or `display`, and `rect` and `noShadow`, as `capture_window` takes them, and `duration` in seconds, where more than 120 records 120. Mark takes `label` (required). Stop and mark take `id`, else the agent's recording in progress. | A [recording of that window or display](#letting-an-agent-capture-and-record). With a `duration`, it waits, then gives the recording's path, length and about 6 key frames, as `get_frames` does. Without one, it gives an `id` at once; stopping it gives the path and frames. A mark gives its `time` in the recording, and the frame there joins the key frames. |

Previews are JPEGs at most 1568 pixels on the long edge and about 1 MB, which is what vision models work at anyway. The key frames from `get_frames` and `record_window` are at most 1024 pixels and 400 KB each, so a dozen fit in one result. The transcript beside them needs macOS 26 and a language with on-device speech recognition. Nothing leaves your Mac, and it asks for no permission, since it reads the saved file rather than the microphone. It hears any speech in the sound, from the microphone or from other apps. The path in the result lets an agent that can read files open the full-size original, and the marks' coordinates are always in the full-size file's pixels.

The server reads only the capture folder: your save folder (`~/Pictures/Shot` by default), or the temporary folder when **Save to folder** is off. It captures or records a window only when you've turned on **Let agents capture and record**, and then only through the running Shot app. It never moves or deletes anything, and never changes a file: `annotate`, `redact`, `edit_image`, `edit_video`, `make_gif`, `trim_video` and `compare` only add a new file beside the capture they start from. It uploads nothing itself. Because the agent starts it, the first time it reads `~/Pictures` macOS may ask whether your terminal or editor can access that folder; allow it, or the agent sees no captures. To check which copy of Shot and which folder it uses, and whether the agent can read that folder, run `/Applications/Shot.app/Contents/MacOS/shot-cli doctor`.

## The `shot` command line

The same `shot` command does the media work without Shot open and without any permission, so an agent with a shell, or a script, can see what happened in a recording, turn it into a GIF for a pull request, or blur something before it shares a screenshot. To put it on your PATH, click **Install** beside **shot command** in **Settings › Agents** and enter your password. Shot links `/usr/local/bin/shot` to the copy inside the app, so the command updates with Shot, and **Uninstall** removes the link. Homebrew installs it for you. Without it, run `/Applications/Shot.app/Contents/MacOS/shot-cli`. Only `shot windows`, `shot capture`, `shot record` and `shot pick` need Shot running, which they open in the background if it isn't. All but `shot pick` need [**Let agents capture and record**](#letting-an-agent-capture-and-record) on.

| Command | Does |
|---|---|
| `shot info <file>` | An image's size and scale, and the record Shot keeps inside a capture, or a video's size, `duration` and `hasAudio` |
| `shot gif <video> [-o out.gif] [--fps 12] [--width 720] [--start 2.5] [--end 9]` | A GIF of the video, or part of it. `--width 0` keeps the video's width. GIFs stop at 60 seconds. |
| `shot trim <video> --start 2.5 --end 9 [-o out.mov]` | The part between two times, as `.mov` or `.mp4`, without re-encoding where it can |
| `shot redact <image> [--rect x,y,w,h …] [--detect email,token,card] [--style blur\|pixelate] [-o out.png]` | Hides each rectangle, given in the image's pixels. `--detect` reads the text on your Mac and hides each email, token or API key, and card number of the kinds you name, and `found` lists each one's kind and box, never its text. If there's nothing to hide, no file is written, `path` is the input and `unchanged` is `true`. Pixelate is the default. |
| `shot frames <video> [--count 8 \| --every 2] [--width 1568] [-o folder]` | Still frames of the video in a new folder, `name frames`, as JPEGs named by their time: by default the first and last and the frame after each change on screen, or with `--every`, one every so many seconds, up to 60 frames |
| `shot text <image>` | The text in the image, read on your Mac: its `size`, all its `text`, and `lines`, each with its `text`, `box`, `confidence` and `words`, each word with its own `box`. Boxes are `[x, y, width, height]` in the image's pixels from the top left. |
| `shot annotate <image> --json marks.json [-o out.png]` | Draws marks, in the [record's format](#using-shot-with-ai-agents) except `image`, as an array or inside an `annotations` object. `--json -` reads them from standard input. |
| `shot diff <a> <b> [-o out.png] [--threshold 0.1]` | Where image `b` differs from `a`. Writes a dimmed copy of `b` with the changes lit up and boxed, `name diff.png` beside `b`, and prints its `path`, the `regions` that changed as `[x, y, width, height]` in `b`'s pixels, `changedPixels`, and `changed`, their share of the image. Images of different sizes are compared at `b`'s size, with a `note` saying so. `--threshold` is how much a colour can change, from 0 to 1, before it counts: 0 counts any difference, and the default, 0.1, ignores anti-aliasing. |
| `shot crop <image> --rect x,y,w,h [-o out.png]` | Keeps that part of the image, given in its pixels, at full resolution. Like a crop in the editor, the new version opens in Shot with the crop still adjustable. |
| `shot edit <image or video> --json edit.json [-o out]` | Makes any of the image editor's changes to an image, from one [edit](#editing-images): crop, pad with a background, style, marks to add, layers to remove, other images to place, scale to 1×, and format. To a video, it makes the [video editor's](#editing-videos): keep or cut, speed, mute, crop, timed marks, videos to append, MP4, MOV or GIF, and a size to fit. `--json -` reads the edit from standard input, and `--json '{"pad": 40}'` takes it as written. |
| `shot windows` | The open windows, front to back, with each one's `app`, `bundleID`, `title`, `size` in points and whether it's `frontmost`, and the `displays`, numbered from 1 |
| `shot latest [--kind image\|video\|any]` | The newest capture, a screenshot unless `--kind` says otherwise: its `name`, `path`, `kind`, when it was `created`, and a `summary` of what Shot recorded in it, as `latest_capture` gives them, without the preview |
| `shot list [--limit 10] [--since 2h] [--query words]` | Recent captures, newest first, as `list_captures` gives them. `--limit` is 1 to 50, and `--since` takes a date such as `2026-10-10` or a span back from now such as `10m`, `2h` or `3d`. `--query` keeps the captures whose name or screenshot text contains the words, with the lines that match, and notes on standard error how many screenshots Shot hasn't read yet. |
| `shot get [<name or path>]` | The capture a file name, a few words of it or its path names, or the newest of any kind, as `get_capture` gives it. If none matches, the error names the closest ones. |
| `shot doctor` | [Checks what agents need](#troubleshooting) and says how to fix each problem |
| `shot capture --window "Simulator"` | A screenshot of the open window whose title or app matches, saved to the capture folder by the running Shot app, which prints its `path`, `size`, `bytes` and `window` (`app` and `title`) |
| `shot capture --bundle-id <id> \| --display <n> [--rect x,y,w,h] [--no-shadow] [--wait-stable[=5]]` | `--bundle-id` takes that app's front window, or with `--window`, the one of its windows that matches. `--display` takes a whole display. `--rect` keeps that part, in points from the top-left corner. `--wait-stable` waits up to 5 seconds, or the time given, for the picture to stop changing, and takes it anyway if it never does. |
| `shot record --window "Simulator" [--duration 10]` | Records that window through Shot. With `--duration`, waits and prints the recording's `path`, `size`, `bytes`, `duration` and `id`; without, prints an `id` at once. At most 10 minutes. It takes `--bundle-id`, `--display`, `--rect` and `--no-shadow` as `shot capture` does. |
| `shot record --window "Simulator" -- <command> [args…]` | Records that window while the command runs, with its output passed through, and stops when it exits. Prints what `--duration` does plus the command's `exitCode`, and `signal` if one ended it, then exits with the command's code. |
| `shot record --mark "tapped Login" [<id>]` | Marks this moment of the agent's recording `id`, or the one in progress, and prints its `time` in seconds. Its key frames then include the frame here, labelled. |
| `shot record --stop [<id>]` | Stops the agent's recording `id`, or the one in progress, and prints what `--duration` does. A recording you stopped yourself still answers with its path for 10 minutes. |
| `shot record --status` | Whether Shot is capturing or recording, and the recording's `id`, `window`, `elapsed` seconds and `byAgent`, plus Shot's `version` and whether it has the `screenRecording` permission |
| `shot watch [--kind image\|video\|any] [--timeout 60] [--follow]` | Waits for your next capture, 60 seconds by default, and prints its `name`, `path`, `kind` and `created`. `shot info` gives the rest. `--follow` prints a line for each capture as it comes, until you stop it or `--timeout` passes. It reads the capture folder only, so Shot needn't be running. |
| `shot pick [--prompt "Select the broken toolbar"] [--timeout 60]` | [Asks you to pick](#letting-an-agent-capture-and-record) an area, window or display on Shot's capture overlay, showing the prompt, then saves the screenshot to the capture folder and prints its `path`, `size`, `bytes` and `window`. Esc, or no pick within the timeout, at most 10 minutes, exits with 66. |

Times are seconds, such as `2.5`, or minutes and seconds, such as `1:02.5`. Without `-o`, the result goes beside the input as its next version, such as `name (2).png`, or `name.gif` for a GIF. Nothing is ever overwritten: an `-o` that exists, or that another program takes while `shot` works, is an error. Without `-o`, a name taken meanwhile moves on to the next one. A redacted, annotated, cropped or edited image opens in Shot with its marks and crop live, as a version you [save](#reopen-a-saved-version) does, and one made from such a version keeps the earlier marks live too. A trim, GIF or edited video opens in the [video editor](#video-editor) with the whole edit still live. Shot keeps these layers in the Application Support folder of the copy of Shot the command belongs to.

Each command prints one JSON object on standard output, and `watch --follow` prints one per line. A command that writes a file gives at least the new file's `path`, its pixel `size` and its `bytes`; `gif` adds `frames` and `truncated`, `trim` adds `duration`, and `edit` adds `layers` for an image, each layer's `id` and `type`, and `duration` for a video, with `frames`, `truncated` and `fps` for a GIF and `scale` for a video fitted to `maxBytes`. `frames` prints the folder's `path` and a `frames` list with each one's `path`, `time`, `size` and `bytes`. Errors go to standard error, as `shot gif: …`, with an exit code for each kind:

| Exit code | Meaning |
|---|---|
| 0 | Done |
| 1 | `shot doctor` found a problem |
| 64 | A wrong option, a missing argument or a value out of range |
| 65 | Not an image or video Shot can read, marks that don't make sense, or a rectangle off the image, window or display |
| 66 | The input file doesn't exist; no open window matches, and the message lists up to 10 open ones; there's no display with that number; or no agent recording has that id, or you discarded it; or `shot watch` saw no new capture in time; or you cancelled `shot pick` or didn't pick in time |
| 69 | Shot isn't answering agents: **Let agents capture and record** is off, Shot couldn't be opened, or it didn't answer in time |
| 70 | Something went wrong inside Shot |
| 73 | The output can't be made: it already exists, or its folder doesn't |
| 74 | Reading or writing failed partway |
| 75 | Shot is busy with a selection, the recording setup or another recording, or the recording to stop is one you started |
| 77 | Shot doesn't have the Screen Recording permission |

`shot record -- <command>` exits with the command's own code instead, as described [above](#letting-an-agent-capture-and-record).

`shot help` and `shot <command> --help` show the options.

Shot still sends nothing anywhere. Whatever an agent reads, though, goes to that agent's model provider, so blur or pixelate anything private before you hand a capture over. `shot redact --detect` and the `redact` tool find emails, tokens and card numbers for you, but only the ones they can read, so check the result before you share it.

## Editing images

`shot edit` and the MCP server's `edit_image` tool make the image editor's changes from one JSON object, so an agent can do in one step what you'd do in the editor. The result is the image's next version. Open it in Shot and every layer is still live: the marks, the placed images, the padding, the style and the crop. Lengths and positions are in the input file's pixels, from its top left, as in the record. Every field is optional, but an edit needs at least one:

```json
{
  "crop": [0, 0, 1600, 1000],
  "pad": 60,
  "background": "white",
  "style": { "shadow": "soft", "border": "hairline", "corners": 16 },
  "marks": [{ "type": "arrow", "from": [410, 220], "to": [612, 388], "color": "red" }],
  "remove": ["5F3A…"],
  "place": [{ "path": "Shot 2026-10-10 at 14.05.40.png", "at": [1700, 0], "width": 800 }],
  "scale": "1x",
  "format": "png"
}
```

| Field | Does |
|---|---|
| `crop` | Keeps `[x, y, width, height]`, applied after everything else, so with `pad` it can keep some of the padding |
| `pad` | Canvas around the image: one number for every side, or `[top, right, bottom, left]`, up to 4096 |
| `background` | Fills the padding: a palette name, a hex such as `#F2F2F7`, or `none` for transparent, which only a PNG can keep |
| `style` | The screenshot's `shadow` (`soft`, `float`, `contact`, `glow` or `none`), `border` (`hairline`, `solid`, `outline` or `none`, or `{"type": "solid", "width": 6, "color": "white"}`) and `corners`, a radius. What's left out stays as it is. An outline needs see-through pixels, and a window captured with its shadow takes no style. |
| `marks` | Marks to draw on top, in the [record's format](#using-shot-with-ai-agents), except `image` |
| `remove` | Layer ids to delete, from the record or an earlier edit's `layers` |
| `place` | Other images to put on top, each `{"path": …}`, with `at`, its top-left corner, else to the right of the image, and `width`, which keeps its proportions, else its own size |
| `scale` | `1x` halves a Retina image to one pixel per point, as [**Scale Retina captures to 1×**](#settings) does. The result keeps its marks in the record but opens flat. |
| `format` | `png` or `jpeg`, else the input's own. A JPEG's padding is white unless `background` says otherwise. |

The changes are made in the editor's order: `remove`, then `marks`, `place`, `style`, `pad`, `background` and last `crop`. A mistake names its field, such as `style.border.width must be pixels above 0` or `marks[2] (arrow): needs from and to, each [x, y]`, and nothing is written. `shot annotate` is an edit with only `marks`, and `shot crop` one with only `crop`.

## Editing videos

For a video, `shot edit` and the MCP server's `edit_video` tool make the video editor's changes and export it, from one JSON object. It's how an agent turns a test recording into pull-request media: cut the dead time, speed it up, mute it, point at the moment the bug happens, and keep it under GitHub's size limit. The result is a new file beside the recording, and **Edit** on it opens the edit in the video editor, still live. Times are seconds of the input, such as `2.5`, or text such as `"1:02.5"`, as `get_frames` and `shot frames` give them. Positions are its pixels, from its top left. Every field is optional, but an edit needs at least one:

```json
{
  "keep": [[2, 9.5], [14, 20]],
  "speed": 2,
  "mute": true,
  "crop": [0, 0, 1600, 1000],
  "marks": [{ "start": 3, "end": 6, "type": "arrow", "from": [410, 220], "to": [612, 388], "color": "red" }],
  "append": ["Recording 2026-10-10 at 14.08.02.mp4"],
  "format": "gif",
  "maxBytes": 10000000,
  "fps": 12,
  "width": 720
}
```

| Field | Does |
|---|---|
| `keep` | The parts to keep, each `[start, end]`, in order. Everything around and between them is cut. |
| `cut` | The parts to cut instead, each `[start, end]` |
| `speed` | How fast it plays, from 0.25 to 4. A GIF can always change speed. An MP4 or MOV can only when it's just kept or cut, as with the editor's export. |
| `mute` | `true` leaves out the sound |
| `crop` | Keeps `[x, y, width, height]` of the picture. The edit opens with the canvas at that size and the recording moved and scaled within it, rather than with the video editor's adjustable frame crop. |
| `marks` | Marks in the [record's format](#using-shot-with-ai-agents), except `image`, each shown from `start` to `end`, or for 3 seconds without one. They're timed and placed in the input, and move with the cuts. |
| `append` | Other videos to play after it, in order |
| `format` | `mp4`, `mov` or `gif`. Without it, an MP4 or MOV keeps its own format, and anything else becomes an MP4. |
| `maxBytes` | The most the file may be, such as `10000000` for 10 MB. A GIF lowers its frame rate, then its width, until it fits. An MP4 or MOV that has to be drawn again, with marks, a crop or appended videos, is drawn at three quarters, then half, then smaller. |
| `fps` and `width` | A GIF's frames per second, 12 by default, and width at most, 720 by default, or 0 for the video's own |

A video that's an earlier edit is edited again from its project, so its marks and cuts stay live. A mistake names its field, such as `keep[1] starts before keep[0] ends` or `speed changes only a GIF, or a video that's only kept or cut`, and nothing is written. `shot trim` is an edit with only `keep`, and `shot gif` one that's a GIF.
