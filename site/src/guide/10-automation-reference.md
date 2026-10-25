---
title: Automation reference
summary: "The MCP server, the shot command, JSON edits, the capture record and the shot:// URL scheme, for agents and scripts."
group: Reference
---

This page is for connecting an agent or writing a script. If you only paste screenshots into an assistant, you don't need it: see [Share a capture with an AI assistant](#share-a-capture-with-an-ai-assistant). For setup in plain steps, see [Work with coding agents](#work-with-coding-agents).

Shot has three ways in:

- Agents that speak MCP use [the MCP server](#the-mcp-server).
- Agents with a shell, and scripts, use [the `shot` command](#the-shot-command-line).
- Launchers, Shortcuts and other apps use [`shot://` links](#url-scheme).

The MCP server and the command share one definition, so what one can do, the other can too.

## The MCP server

Shot comes with a small [MCP](https://modelcontextprotocol.io) server, so you can ask an agent "what did I mark in my latest screenshot?" without pasting anything.

### Add it to your agent

1. Open **Settings › Agents**. The **MCP server** card lists each assistant and agent it finds on your Mac, plus a setup any other app can use. If it finds none, it lists them all.
2. Click **Install** beside yours. The row then shows **Installed**. If it shows **Update**, the setup points at a copy of Shot that has moved, so click it to fix that.
3. Restart the app if Shot asks you to. Claude only reads its setup when it opens.

How Install adds Shot depends on the app:

| App | What Install does |
|---|---|
| Claude, Devin (formerly Windsurf) | Adds Shot to the app's config file, after saving a copy of the file beside it with `.bak` on the end. If the file isn't valid JSON, Shot leaves it alone. |
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

### What it needs

- The server runs only while the agent uses it, and works whether Shot is open or not.
- It needs no setting turned on. Without [**Hand captures to agents**](#hand-captures-to-agents), Shot has no record of where a capture came from or what you marked, but the agent still sees the image.
- Only `list_windows`, `capture_window` and `record_window` need [**Let agents capture and record**](#let-an-agent-capture-and-record). They and `ask_for_capture` open Shot in the background if it isn't running.

> [!TIP]
> The first time the server reads `~/Pictures`, macOS may ask whether your terminal or editor can access that folder. Allow it, or the agent sees no captures. To check which copy of Shot and which folder the server uses, and whether the agent can read it, run `/Applications/Shot.app/Contents/MacOS/shot-cli doctor`.

### Tools

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
| `wait_for_capture` | `kind`: `image`, `video` or `any` (the default); `timeout`: up to 120 seconds, 60 by default | Waits for you to send it a capture, then returns it as `latest_capture` does, after what you want done, so an agent can ask you to "screenshot the broken toolbar" and carry on once you have. While Shot is running, the agent's name shows on **Send to …** in the Quick Access, editor and gallery menus, and the capture goes to it when you choose that, with your notes and marks as the task. With `kind` set to `video`, or if Shot isn't running, the next capture saved in the folder counts instead, and a recording counts once Shot has finished writing it. If nothing comes in time, it says so, and the agent can call again. |
| `ask_for_capture` | `prompt`: what to select, up to 100 characters, such as `Select the broken toolbar`; `timeout`: up to 120 seconds, 60 by default | [Asks you to pick](#ask-you-to-pick) an area, window or display, showing the prompt and the agent's name, then returns the screenshot as `capture_window` does. If you press Esc or don't pick in time, it says so. Works with **Let agents capture and record** off. |
| `annotate` | `annotations` (required): marks in the [record's format](#the-capture-record), except `image`; `path` or `name`, else the newest screenshot | A copy with the marks drawn on, saved as the screenshot's next version, and a preview of it. Open it in Shot and the marks are still live, along with any already on a version you [saved](#reopen-a-saved-version). |
| `redact` | `detect`: a list of `email`, `token` (tokens and API keys) and `card` (card numbers), all three by default, or none when `rects` are given; `rects`: areas to hide as well, each `[x, y, width, height]` in the file's pixels; `style`: `pixelate` (the default) or `blur`; `path` or `name`, else the newest screenshot | A copy with each email, token and card number it reads hidden, saved as the screenshot's next version, and a preview of it, so an agent can hide private text before it reads a capture. Each find comes with its kind and box, never its text. If there's nothing to hide, no file is written. Open the copy in Shot and the hidden areas are layers you can move or remove. |
| `edit_image` | Any of the [edit's fields](#edit-an-image): `crop`, `pad`, `background`, `style`, `marks`, `remove`, `place`, `scale` and `format`; `path` or `name`, else the newest screenshot. `place` takes other screenshots in the capture folder, by path or a few words of the name. | A copy with every change made, as you'd make it in the editor, saved as the screenshot's next version, and a preview of it, with each layer's `id` and `type` in `layers`. Open it in Shot and the marks, placed screenshots, padding, style and crop are all still live. |
| `edit_video` | Any of the [video edit's fields](#edit-a-video): `keep` or `cut`, `speed`, `mute`, `crop`, `marks`, `append`, `format`, `maxBytes`, and a GIF's `fps` and `width`; `path` or `name`, else the newest recording. `append` takes other recordings in the capture folder, by path or a few words of the name. | A new file beside the recording with every change made, as the video editor and its export make them: its `path`, `size`, `bytes` and `duration`, and for a GIF its `frames` and `fps`. **Edit** on it opens the edit in the video editor, still live. |
| `make_gif` | `path` or `name`, else the newest recording; `start`, `end` in seconds; `fps`, 1 to 30, 12 by default; `width`, 720 by default, or 0 for the recording's own | A GIF of the recording, or part of it, saved beside it. GIFs stop at 60 seconds. **Edit** on it opens the trim in the video editor. |
| `trim_video` | `start` and `end` in seconds (required); `path` or `name`, else the newest recording | The part between the two times, saved beside the recording, without re-encoding where it can. It opens in the video editor with the trim still adjustable. |
| `compare` | `a` and `b` (required): the screenshots before and after, each a path or a few words of its name; `threshold`, 0 to 1, 0.1 by default | Where `b` differs from `a`, to check that a fix changed only what it should. The diff image is a dimmed copy of `b` with the changes lit up and boxed, saved beside `b` as `name diff.png`. With it come each changed region as `[x, y, width, height]` in `b`'s pixels and the share of pixels that changed. Screenshots of different sizes are compared at `b`'s size, and the result says so. |
| `list_windows` | None | The open windows, front to back: each one's `app`, `bundleID`, `title`, `size` in points and whether it's `frontmost`, and the `displays`, numbered from 1, with their size and scale |
| `capture_window` | One of `window`, a few words of the window's title or its app, such as `Simulator`, or `bundleID`, for that app's front window (with `window` too, the one of its windows that matches), or `display`, a number from `list_windows`. Also `rect`, as `[x, y, width, height]` in points from the top-left corner, `noShadow`, and `waitStable`, the most seconds to wait for the picture to stop changing, up to 30 | A [screenshot of that window or display](#screenshot-a-window), saved to the capture folder: a preview, its path and size, and which app and window it was. If no window matches, the error lists the open ones. |
| `record_window` | `action`: `start` (the default), `stop` or `mark`. Start takes a `window`, `bundleID` or `display`, and `rect` and `noShadow`, as `capture_window` takes them, and `duration` in seconds, where more than 120 records 120. Mark takes `label` (required). Stop and mark take `id`, else the agent's recording in progress. | A [recording of that window or display](#record-a-window-as-it-runs). With a `duration`, it waits, then gives the recording's path, length and about 6 key frames, as `get_frames` does. Without one, it gives an `id` at once; stopping it gives the path and frames. A mark gives its `time` in the recording, and the frame there joins the key frames. |

### Previews and transcripts

Previews are JPEGs at most 1568 pixels on the long edge and about 1 MB, which is what vision models work at anyway. The key frames from `get_frames` and `record_window` are at most 1024 pixels and 400 KB each, so a dozen fit in one result. The transcript beside them needs macOS 26 and a language with on-device speech recognition. Nothing leaves your Mac, and it asks for no permission, since it reads the saved file rather than the microphone. It hears any speech in the sound, from the microphone or from other apps. The path in the result lets an agent that can read files open the full-size original, and the marks' coordinates are always in the full-size file's pixels.

### What it can and can't touch

The server reads only the capture folder: your save folder (`~/Pictures/Shot` by default), or the temporary folder when **Save to folder** is off. It captures or records a window only when you've turned on **Let agents capture and record**, and then only through the running Shot app. It never moves or deletes anything, and never changes a file: `annotate`, `redact`, `edit_image`, `edit_video`, `make_gif`, `trim_video` and `compare` only add a new file beside the capture they start from. It uploads nothing itself.

## The shot command line

The `shot` command does Shot's media work from a shell, without Shot open and without any permission. An agent with a shell, or a script, can see what happened in a recording, turn it into a GIF for a pull request, or blur something before it shares a screenshot.

### Install it

1. Open **Settings › Agents**.
2. Click **Install** beside **shot command**, and enter your password.

Shot links `/usr/local/bin/shot` to the copy inside the app, so the command updates with Shot. **Uninstall** removes the link. If you installed Shot with Homebrew, `shot` is already there. Without the link, run `/Applications/Shot.app/Contents/MacOS/shot-cli`.

`shot help` and `shot <command> --help` show the options.

### Commands

#### Read your captures

These only read, so Shot needn't be running.

| Command | Does |
|---|---|
| `shot info <file>` | An image's size and scale, and the record Shot keeps inside a capture, or a video's size, `duration` and `hasAudio` |
| `shot latest [--kind image\|video\|any]` | The newest capture, a screenshot unless `--kind` says otherwise: its `name`, `path`, `kind`, when it was `created`, and a `summary` of what Shot recorded in it, as `latest_capture` gives them, without the preview |
| `shot list [--limit 10] [--since 2h] [--query words]` | Recent captures, newest first, as `list_captures` gives them. `--limit` is 1 to 50, and `--since` takes a date such as `2026-10-10` or a span back from now such as `10m`, `2h` or `3d`. `--query` keeps the captures whose name or screenshot text contains the words, with the lines that match, and notes on standard error how many screenshots Shot hasn't read yet. |
| `shot get [<name or path>]` | The capture a file name, a few words of it or its path names, or the newest of any kind, as `get_capture` gives it. If none matches, the error names the closest ones. |
| `shot watch [--kind image\|video\|any] [--timeout 60] [--follow]` | Waits for your next capture, 60 seconds by default, and prints its `name`, `path`, `kind` and `created`. `shot info` gives the rest. `--follow` prints a line for each capture as it comes, until you stop it or `--timeout` passes. It reads the capture folder only, so Shot needn't be running. |
| `shot text <image>` | The text in the image, read on your Mac: its `size`, all its `text`, and `lines`, each with its `text`, `box`, `confidence` and `words`, each word with its own `box`. Boxes are `[x, y, width, height]` in the image's pixels from the top left. |
| `shot frames <video> [--count 8 \| --every 2] [--width 1568] [-o folder]` | Still frames of the video in a new folder, `name frames`, as JPEGs named by their time: by default the first and last and the frame after each change on screen, or with `--every`, one every so many seconds, up to 60 frames |

#### Make new files

These write a new file beside the input and never change it. Shot needn't be running.

| Command | Does |
|---|---|
| `shot gif <video> [-o out.gif] [--fps 12] [--width 720] [--start 2.5] [--end 9]` | A GIF of the video, or part of it. `--width 0` keeps the video's width. GIFs stop at 60 seconds. |
| `shot trim <video> --start 2.5 --end 9 [-o out.mov]` | The part between two times, as `.mov` or `.mp4`, without re-encoding where it can |
| `shot redact <image> [--rect x,y,w,h …] [--detect email,token,card] [--style blur\|pixelate] [-o out.png]` | Hides each rectangle, given in the image's pixels. `--detect` reads the text on your Mac and hides each email, token or API key, and card number of the kinds you name, and `found` lists each one's kind and box, never its text. If there's nothing to hide, no file is written, `path` is the input and `unchanged` is `true`. Pixelate is the default. |
| `shot annotate <image> --json marks.json [-o out.png]` | Draws marks, in the [record's format](#the-capture-record) except `image`, as an array or inside an `annotations` object. `--json -` reads them from standard input. |
| `shot crop <image> --rect x,y,w,h [-o out.png]` | Keeps that part of the image, given in its pixels, at full resolution. Like a crop in the editor, the new version opens in Shot with the crop still adjustable. |
| `shot diff <a> <b> [-o out.png] [--threshold 0.1]` | Where image `b` differs from `a`. Writes a dimmed copy of `b` with the changes lit up and boxed, `name diff.png` beside `b`, and prints its `path`, the `regions` that changed as `[x, y, width, height]` in `b`'s pixels, `changedPixels`, and `changed`, their share of the image. Images of different sizes are compared at `b`'s size, with a `note` saying so. `--threshold` is how much a colour can change, from 0 to 1, before it counts: 0 counts any difference, and the default, 0.1, ignores anti-aliasing. |
| `shot edit <image or video> --json edit.json [-o out]` | Makes any of the image editor's changes to an image, from one [edit](#edit-an-image): crop, pad with a background, style, marks to add, layers to remove, other images to place, scale to 1×, and format. To a video, it makes the [video editor's](#edit-a-video): keep or cut, speed, mute, crop, timed marks, videos to append, MP4, MOV or GIF, and a size to fit. `--json -` reads the edit from standard input, and `--json '{"pad": 40}'` takes it as written. |

#### Capture and record through Shot

These ask the running Shot app, and open it in the background if it isn't running. All but `shot pick` need [**Let agents capture and record**](#let-an-agent-capture-and-record) on.

| Command | Does |
|---|---|
| `shot windows` | The open windows, front to back, with each one's `app`, `bundleID`, `title`, `size` in points and whether it's `frontmost`, and the `displays`, numbered from 1 |
| `shot capture --window "Simulator"` | A screenshot of the open window whose title or app matches, saved to the capture folder by the running Shot app, which prints its `path`, `size`, `bytes` and `window` (`app` and `title`) |
| `shot capture --bundle-id <id> \| --display <n> [--rect x,y,w,h] [--no-shadow] [--wait-stable[=5]]` | `--bundle-id` takes that app's front window, or with `--window`, the one of its windows that matches. `--display` takes a whole display. `--rect` keeps that part, in points from the top-left corner. `--wait-stable` waits up to 5 seconds, or the time given, for the picture to stop changing, and takes it anyway if it never does. |
| `shot record --window "Simulator" [--duration 10]` | Records that window through Shot. With `--duration`, waits and prints the recording's `path`, `size`, `bytes`, `duration` and `id`; without, prints an `id` at once. At most 10 minutes. It takes `--bundle-id`, `--display`, `--rect` and `--no-shadow` as `shot capture` does. |
| `shot record --window "Simulator" -- <command> [args…]` | Records that window while the command runs, with its output passed through, and stops when it exits. Prints what `--duration` does plus the command's `exitCode`, and `signal` if one ended it, then exits with the command's code. |
| `shot record --mark "tapped Login" [<id>]` | Marks this moment of the agent's recording `id`, or the one in progress, and prints its `time` in seconds. Its key frames then include the frame here, labelled. |
| `shot record --stop [<id>]` | Stops the agent's recording `id`, or the one in progress, and prints what `--duration` does. A recording you stopped yourself still answers with its path for 10 minutes. |
| `shot record --status` | Whether Shot is capturing or recording, and the recording's `id`, `window`, `elapsed` seconds and `byAgent`, plus Shot's `version` and whether it has the `screenRecording` permission |
| `shot pick [--prompt "Select the broken toolbar"] [--timeout 60]` | [Asks you to pick](#ask-you-to-pick) an area, window or display on Shot's capture overlay, showing the prompt, then saves the screenshot to the capture folder and prints its `path`, `size`, `bytes` and `window`. Esc, or no pick within the timeout, at most 10 minutes, exits with 66. |

#### Check your setup

| Command | Does |
|---|---|
| `shot doctor` | [Checks what agents need](#troubleshooting) and says how to fix each problem |

### Times, files and versions

Times are seconds, such as `2.5`, or minutes and seconds, such as `1:02.5`. Without `-o`, the result goes beside the input as its next version, such as `name (2).png`, or `name.gif` for a GIF. Nothing is ever overwritten: an `-o` that exists, or that another program takes while `shot` works, is an error. Without `-o`, a name taken meanwhile moves on to the next one. A redacted, annotated, cropped or edited image opens in Shot with its marks and crop live, as a version you [save](#reopen-a-saved-version) does, and one made from such a version keeps the earlier marks live too. A trim, GIF or edited video opens in the [video editor](#edit-a-recording) with the whole edit still live. Shot keeps these layers in the Application Support folder of the copy of Shot the command belongs to.

### Output

Each command prints one JSON object on standard output, and `watch --follow` prints one per line. A command that writes a file gives at least the new file's `path`, its pixel `size` and its `bytes`; `gif` adds `frames` and `truncated`, `trim` adds `duration`, and `edit` adds `layers` for an image, each layer's `id` and `type`, and `duration` for a video, with `frames`, `truncated` and `fps` for a GIF and `scale` for a video fitted to `maxBytes`. `frames` prints the folder's `path` and a `frames` list with each one's `path`, `time`, `size` and `bytes`.

### Exit codes

Errors go to standard error, as `shot gif: …`, with an exit code for each kind:

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

`shot record -- <command>` exits with the command's own code instead, as described in [Record while a command runs](#record-while-a-command-runs).

## Edit captures with JSON

`shot edit` and the MCP server's `edit_image` and `edit_video` tools make the editors' changes from one JSON object, so an agent can do in one step what you'd do by hand. The result opens in Shot with every layer still live.

### Edit an image

The result is the image's next version. Open it in Shot and every layer is still live: the marks, the placed images, the padding, the style and the crop. Lengths and positions are in the input file's pixels, from its top left, as in the record. Every field is optional, but an edit needs at least one:

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
| `marks` | Marks to draw on top, in the [record's format](#the-capture-record), except `image` |
| `remove` | Layer ids to delete, from the record or an earlier edit's `layers` |
| `place` | Other images to put on top, each `{"path": …}`, with `at`, its top-left corner, else to the right of the image, and `width`, which keeps its proportions, else its own size |
| `scale` | `1x` halves a Retina image to one pixel per point, as [**Scale Retina captures to 1×**](#settings) does. The result keeps its marks in the record but opens flat. |
| `format` | `png` or `jpeg`, else the input's own. A JPEG's padding is white unless `background` says otherwise. |

The changes are made in the editor's order: `remove`, then `marks`, `place`, `style`, `pad`, `background` and last `crop`. A mistake names its field, such as `style.border.width must be pixels above 0` or `marks[2] (arrow): needs from and to, each [x, y]`, and nothing is written. `shot annotate` is an edit with only `marks`, and `shot crop` one with only `crop`.

### Edit a video

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
| `marks` | Marks in the [record's format](#the-capture-record), except `image`, each shown from `start` to `end`, or for 3 seconds without one. They're timed and placed in the input, and move with the cuts. |
| `append` | Other videos to play after it, in order |
| `format` | `mp4`, `mov` or `gif`. Without it, an MP4 or MOV keeps its own format, and anything else becomes an MP4. |
| `maxBytes` | The most the file may be, such as `10000000` for 10 MB. A GIF lowers its frame rate, then its width, until it fits. An MP4 or MOV that has to be drawn again, with marks, a crop or appended videos, is drawn at three quarters, then half, then smaller. |
| `fps` and `width` | A GIF's frames per second, 12 by default, and width at most, 720 by default, or 0 for the video's own |

A video that's an earlier edit is edited again from its project, so its marks and cuts stay live. A mistake names its field, such as `keep[1] starts before keep[0] ends` or `speed changes only a GIF, or a video that's only kept or cut`, and nothing is written. `shot trim` is an edit with only `keep`, and `shot gif` one that's a GIF.

## The capture record

The record is stored in the image's own metadata, as JSON in the XMP property `shot:record` (namespace `https://shot.lorcanchinnock.com/ns/capture/1.0/`), so there's no extra file in your capture folder and it goes wherever the file goes. A copy of a PNG capture keeps it too, but a copy of a JPEG capture or of a styled capture doesn't, since those are new PNGs. It follows the `shot.capture/2` schema:

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
- `lineWidth`, `fill`, `fontSize`, `amount` (a blur's or pixelation's strength), `bend` and `cornerRadius` (a shape's rounded corners) are there so Shot can rebuild a mark; an agent can ignore them. On text, `fill` is the colour of a box behind it, as captions have.
- `id` names the layer, and an [edit's](#edit-an-image) `remove` takes it. Marks an agent writes can leave it out.

> [!NOTE]
> Development builds before 0.7.0-beta.40 wrote this as a `.shot.json` file beside each capture instead. Nothing reads those any more, so you can delete them.

## URL scheme

Every action in Shot has a `shot://` link, so you can run it without the keyboard: from a launcher, the Shortcuts app, or a script.

### Try it

Open Terminal and run:

```sh
open "shot://capture-area"
```

Shot starts an area screenshot, just as <kbd>⌘⇧4</kbd> does.

### Every link

| URL | Action |
|---|---|
| `shot://capture-area`, `capture-fullscreen`, `capture-window` | Take a screenshot |
| `shot://capture-previous` | Take the last area screenshot's area again |
| `shot://record`, `record-fullscreen`, `record-window` | Set up, confirm, or stop a recording |
| `shot://pause` | Pause or resume the recording |
| `shot://pick-color` | Pick a colour on screen and copy its hex |
| `shot://copy-path` | Copy the newest capture's path |
| `shot://copy-text` | Drag out an area and copy the text in it |
| `shot://focus-quick-access` | Use the newest [Quick Access](#quick-access) card from the keyboard |
| `shot://capture-timer?seconds=<n>` | Count down `n` seconds (1 to 60, default 5), then capture the full screen |
| `shot://annotate?path=<file>` | Open an image in the editor, or a video in the video editor |
| `shot://edit-video?path=<file>` | Open a video in the video editor to trim it |
| `shot://send-to-agent?path=<file>` | Open your coding agent with the screenshot, as [Send to Agent](#send-a-capture-to-your-coding-agent) does. Works only while it's on in **Settings › Agents** |
| `shot://gallery` | Open the gallery |
| `shot://settings?section=<name>` | Open Settings at `gallery`, `general`, `capture`, `quickAccess`, `recording`, `agents`, `shortcuts`, or `about` |
| `shot://welcome` | Open the [welcome window](#follow-the-welcome-window) again |

### Paths and errors

- `path` can start with `~`.
- URL-encode spaces and other special characters, for example `open "shot://annotate?path=~/Desktop/My%20Shot.png"`.
- The older `shot://record?full=1` still works, and does the same as `shot://record-fullscreen`.
- An unknown action or settings section, or `annotate`, `edit-video` or `send-to-agent` without a `path`, shows an error instead.

### For AI agents

`shot://capture-window` and `record-window` open the window picker for you to click a window. To capture or record a named window without a click, an agent uses its `capture_window` and `record_window` tools, or `shot capture` and `shot record`, once you've turned on [**Let agents capture and record**](#let-an-agent-capture-and-record).
