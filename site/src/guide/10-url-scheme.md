---
title: URL scheme
summary: "Run any action from a shot:// link, in a script, a launcher or another app."
group: Reference
---

Use `open "shot://…"` to run Shot from a launcher, the Shortcuts app, or a script:

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
| `shot://gallery` | Open the gallery |
| `shot://settings?section=<name>` | Open Settings at `gallery`, `general`, `capture`, `quickAccess`, `recording`, `agents`, `shortcuts`, or `about` |
| `shot://welcome` | Open the [welcome window](#first-launch) again |

For AI agents, `shot mcp` is an MCP server for your captures; see [The MCP server](#the-mcp-server). Install the `shot` command from **Settings › Agents**, or let Homebrew install it for you; without it, run `Shot.app/Contents/MacOS/shot-cli mcp`. The same command also makes GIFs, trims, redacts, annotates, pulls key frames and reads text without the app; see [The `shot` command line](#the-shot-command-line). `shot://capture-window` and `record-window` open the window picker for you to click a window. An agent's `capture_window` and `record_window` tools, and `shot capture` and `shot record`, skip the picker and take the window they name, once you've turned on [**Let agents capture and record**](#letting-an-agent-capture-and-record).

`path` can start with `~`. URL-encode spaces and other special characters, for example `open "shot://annotate?path=~/Desktop/My%20Shot.png"`. The older `shot://record?full=1` still works and does the same as `shot://record-fullscreen`. An unknown action or settings section, or `annotate` or `edit-video` without a `path`, shows an error instead.
