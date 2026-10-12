<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Shot app icon">
</p>

<h1 align="center">Shot <sup>beta</sup></h1>

<p align="center">
  Screenshots, annotations, and screen recordings for macOS, from the menu bar.<br>
  Free, open source, and private: no account, no cloud, no analytics.
</p>

<p align="center">
  <a href="https://github.com/LorcanChinnock/shot/releases/latest"><img src="https://img.shields.io/github/v/release/LorcanChinnock/shot?label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/status-beta-yellow" alt="Beta">
  <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0 license"></a>
  <a href="https://github.com/sponsors/LorcanChinnock"><img src="https://img.shields.io/badge/sponsor-%E2%99%A5-ea4aaa" alt="Sponsor Shot"></a>
</p>

<p align="center">
  <a href="https://github.com/LorcanChinnock/shot/releases/latest"><b>Download Shot for macOS</b></a>
</p>

<p align="center">
  <img src="docs/media/hero.gif" width="720" alt="Capturing an order with ⌘⇧4, opening it from the Quick Access card, adding an arrow and a note, then pasting it into a chat">
</p>

### Capture and Quick Access

Pick an area on a frozen screen with a magnifier, or a window or the full screen. Shot copies and saves it as soon as you let go, and a card in the corner lets you annotate it, save it somewhere else, or drag it straight into another app.

<img src="docs/media/capture.gif" width="720" alt="Dragging out an area with the magnifier, then the Quick Access card sliding into the corner and showing its buttons">

### Annotate anything

Arrows, sticky notes, blur and pixelate, a spotlight, a pen and more, with room to annotate outside the screenshot and to combine several images on one canvas.

<img src="docs/media/editor.png" width="720" alt="The annotation editor with a blurred email address, a highlighted line, numbered counters, an arrow and a sticky note beside the screenshot">

### Record your screen, and yourself

Record an area, a screen or a window to MP4, with your microphone, system audio, and a round camera bubble.

<img src="docs/media/recording.gif" width="720" alt="Picking an area to record, then the recording outline, the controls and the round camera bubble while a chart animates">

### Trim and export to GIF

Trim a recording, cut sections out, draw over it, add music or other clips, and export an MP4 or a GIF at the frame rate, width and speed you choose.

<img src="docs/media/video-editor.png" width="720" alt="The video editor with a trimmed start, a cut, an arrow over the video, an audio track and the GIF export options">

### Works with AI agents

Circle the bug, copy, and paste it into Claude Code, Codex or Cursor: your arrows and notes show the agent exactly where to look. Turn on **Hand captures to agents** and each screenshot also records, inside the image, which app it came from and what you circled, and where. Or let the agent look for itself through Shot's MCP server: `claude mcp add shot -- /Applications/Shot.app/Contents/MacOS/shot-cli mcp`, or `claude mcp add shot -- shot mcp` after a Homebrew install. Agents can't watch video, so `shot frames` hands them the key frames of a recording. Turn on **Let agents capture and record** and an agent can screenshot or record a window, such as the Simulator, with `shot capture --window Simulator` or `shot record --window Simulator --duration 10`, then see what happened in its key frames. Shot tells you each time. The same `shot` command makes GIFs, trims, redacts and annotates with no window open, and never overwrites a file. See [Using Shot with AI agents](docs/usage.md#using-shot-with-ai-agents).

<img src="docs/media/agents-settings.png" width="720" alt="Settings › Agents with Hand captures to agents and Let agents capture and record turned on, and the MCP setup commands for Claude Code, Cursor and Codex, each with a Copy button">

## Install

Shot needs macOS 15 or later and an Apple Silicon Mac. It doesn't run on Intel Macs.

**With [Homebrew](https://brew.sh):**

```sh
brew update && brew install lorcanchinnock/tap/shot
```

**Or by hand:** download `Shot-v<version>.zip` from the [latest release](https://github.com/LorcanChinnock/shot/releases/latest), unzip it, and move **Shot.app** to Applications.

### First launch

1. Open Shot from Applications. Releases aren't notarized by Apple yet, so macOS says it can't verify Shot. Click **Done**.
2. In **System Settings › Privacy & Security**, scroll down to the message about Shot, click **Open Anyway**, then confirm. You only do this once.

   <img src="docs/media/open-anyway.png" width="495" alt="Privacy & Security in System Settings, with the Open Anyway button next to the message that Shot was blocked">

3. In Shot's welcome window, click **Grant**, then **Open System Settings** in the macOS prompt, and turn on Shot. Back in Shot's window, click **Relaunch**: macOS applies the permission only after a relaunch.
4. Choose whether Shot takes over ⌘⇧3 to ⌘⇧5 (macOS gets them back when Shot quits) and opens at login, then click **Continue**.
5. Shot now lives in the menu bar. Press ⌘⇧4 and drag out an area to take your first screenshot; the window shows a few tips once it's done. See [First launch](docs/usage.md#first-launch) for more.

Shot updates itself once you allow it to; see [Updates](docs/usage.md#updates). To uninstall, see [Removing Shot](docs/usage.md#removing-shot), or quit Shot and run `brew uninstall --zap shot` if you used Homebrew.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧3 | Capture the full screen |
| ⌘⇧4 | Capture an area. Press Space to pick a window instead. |
| ⌘⇧5 | Record an area. Press Space to pick a window, or Enter for the full screen. |

Shot takes these keys over from macOS. To keep the macOS screenshot tool, and for every other shortcut, see [Keyboard shortcuts](docs/usage.md#keyboard-shortcuts).

## More

- **[User guide](docs/usage.md):** every feature, shortcut and setting, plus the `shot://` URL scheme.
- **[Privacy](docs/usage.md#privacy):** no analytics; the network is used only to check for updates, after you agree.
- **[Contributing](CONTRIBUTING.md):** build from source, run the tests, and send a change.
- **[Sponsor](https://github.com/sponsors/LorcanChinnock):** Shot is free; sponsoring helps pay to notarize it.
- **[License](LICENSE):** free software under the GNU General Public License v3.0.
