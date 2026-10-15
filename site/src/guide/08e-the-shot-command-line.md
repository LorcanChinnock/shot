---
title: The shot command line
summary: "Every shot command, for agents and scripts that work in a shell: read, edit, capture and record."
group: AI agents
---

The `shot` command does Shot's media work from a shell, without Shot open and without any permission. An agent with a shell, or a script, can see what happened in a recording, turn it into a GIF for a pull request, or blur something before it shares a screenshot.

## Install it

1. Open **Settings › Agents**.
2. Click **Install** beside **shot command**, and enter your password.

Shot links `/usr/local/bin/shot` to the copy inside the app, so the command updates with Shot. **Uninstall** removes the link. If you installed Shot with Homebrew, `shot` is already there. Without the link, run `/Applications/Shot.app/Contents/MacOS/shot-cli`.

`shot help` and `shot <command> --help` show the options.

## Commands

### Read your captures

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

### Make new files

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

### Capture and record through Shot

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

### Check your setup

| Command | Does |
|---|---|
| `shot doctor` | [Checks what agents need](#troubleshooting) and says how to fix each problem |

## Times, files and versions

Times are seconds, such as `2.5`, or minutes and seconds, such as `1:02.5`. Without `-o`, the result goes beside the input as its next version, such as `name (2).png`, or `name.gif` for a GIF. Nothing is ever overwritten: an `-o` that exists, or that another program takes while `shot` works, is an error. Without `-o`, a name taken meanwhile moves on to the next one. A redacted, annotated, cropped or edited image opens in Shot with its marks and crop live, as a version you [save](#reopen-a-saved-version) does, and one made from such a version keeps the earlier marks live too. A trim, GIF or edited video opens in the [video editor](#edit-a-recording) with the whole edit still live. Shot keeps these layers in the Application Support folder of the copy of Shot the command belongs to.

## Output

Each command prints one JSON object on standard output, and `watch --follow` prints one per line. A command that writes a file gives at least the new file's `path`, its pixel `size` and its `bytes`; `gif` adds `frames` and `truncated`, `trim` adds `duration`, and `edit` adds `layers` for an image, each layer's `id` and `type`, and `duration` for a video, with `frames`, `truncated` and `fps` for a GIF and `scale` for a video fitted to `maxBytes`. `frames` prints the folder's `path` and a `frames` list with each one's `path`, `time`, `size` and `bytes`.

## Exit codes

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
