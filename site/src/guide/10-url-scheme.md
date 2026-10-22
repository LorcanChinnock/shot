---
title: URL scheme
summary: "Run any action from a shot:// link, in a script, a launcher or another app."
group: Reference
---

Every action in Shot has a `shot://` link, so you can run it without the keyboard: from a launcher, the Shortcuts app, or a script.

## Try it

Open Terminal and run:

```sh
open "shot://capture-area"
```

Shot starts an area screenshot, just as <kbd>⌘⇧4</kbd> does.

## Every link

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

## Paths and errors

- `path` can start with `~`.
- URL-encode spaces and other special characters, for example `open "shot://annotate?path=~/Desktop/My%20Shot.png"`.
- The older `shot://record?full=1` still works, and does the same as `shot://record-fullscreen`.
- An unknown action or settings section, or `annotate`, `edit-video` or `send-to-agent` without a `path`, shows an error instead.

## For AI agents and scripts

`shot://capture-window` and `record-window` open the window picker for you to click a window. To capture or record a named window without a click, an agent uses its `capture_window` and `record_window` tools, or `shot capture` and `shot record`, once you've turned on [**Let agents capture and record**](#let-an-agent-capture-and-record).

The `shot` command also makes GIFs, trims, redacts, annotates, pulls key frames and reads text without the app, and `shot mcp` is an MCP server for your captures. See [The shot command line](#the-shot-command-line) and [The MCP server](#the-mcp-server). Install the command from **Settings › Agents**, or let Homebrew install it for you; without it, run `Shot.app/Contents/MacOS/shot-cli`.
