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
  <a href="https://github.com/LorcanChinnock/shot/releases/latest"><b>Download</b></a> ·
  <a href="https://shot.lorcanchinnock.com">Website</a> ·
  <a href="https://shot.lorcanchinnock.com/docs/get-started/">User guide</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <img src="docs/media/hero.gif" width="720" alt="Capturing an order with ⌘⇧4, opening it from the Quick Access card, highlighting the discount and pointing an arrow at the $0, then pasting it into a chat">
</p>

## Features

- **Capture:** an area on a frozen screen with a magnifier, a window, or the whole screen, with a delay if you need one. Shot copies and saves it as soon as you let go.
- **Capture a long page:** turn on Scroll, pick the part of the screen that scrolls and scroll it yourself, in any direction. Shot builds one screenshot as you go, keeps sticky headers and columns once, and shows you what you haven't covered yet.
- **Quick Access:** a card in the corner after every capture. Annotate it, pin it above your other windows, or drag it straight into another app.
- **Annotate:** arrows, text, sticky notes, highlights, a spotlight, blur and pixelate, and several images on one canvas.
- **Record:** an area, a window or a screen to MP4, with your microphone, the sound from your Mac and a camera bubble.
- **Edit video and make GIFs:** trim, cut, crop, speed up and draw over a recording, then export an MP4 or a GIF.
- **Organise:** browse every capture in the gallery, search the text in screenshots, and group captures into folders and Finder tags when you want to.
- **Ask an AI assistant:** paste a marked-up screenshot into Claude or ChatGPT, or copy its path for an assistant that can open files.
- **Light or dark:** Shot follows your Mac's appearance, or you can pick one in Settings.
- **Private:** no account, no cloud and no analytics. Shot only goes online to check for updates, once you agree.

### Capture and Quick Access

<img src="docs/media/capture.gif" width="720" alt="Pressing Tab to step the capture between an area, a window and the full screen, dragging out an area with the magnifier, then the Quick Access card sliding into the corner and showing its buttons">

### Annotate anything

<img src="docs/media/editor.png" width="720" alt="The annotation editor with a blurred email address, the discount line highlighted, and a sticky note with an arrow pointing at it">

### Record your screen, and yourself

<img src="docs/media/recording.gif" width="720" alt="Stepping the Delay chip through its choices, picking an area to record, then the recording outline and the controls while a chart animates">

### Trim and export to GIF

<img src="docs/media/video-editor.png" width="720" alt="The video editor with a cut where the recording went to another page, a Best day label and an arrow over the video, and the GIF export options">

## Install

**Requirements:** macOS 15 or later, on an Apple Silicon or Intel Mac. Intel support is best effort: Shot is built for Intel but not tested on it, so please report anything that breaks.

Paste this into Terminal. It downloads the latest release, checks it against the release's checksum, and copies Shot into Applications:

```sh
curl -fsSL https://shot.lorcanchinnock.com/install.sh | bash
```

Shot opens straight away, and a short welcome window asks for the screen recording permission and sets up your shortcuts. [Get started](https://shot.lorcanchinnock.com/docs/get-started/) walks through each step.

**Or by hand:** download `Shot-v<version>.zip` from the [latest release](https://github.com/LorcanChinnock/shot/releases/latest), unzip it, and move **Shot.app** to Applications. Apple hasn't notarized Shot, and a browser download is checked by macOS, so the first time you open it macOS says it can't verify Shot. Click **Done**, then **Open Anyway** in **System Settings › Privacy & Security**. The command above skips this, because Terminal downloads aren't checked that way.

Shot updates itself once you allow it to. To uninstall, see [Removing Shot](https://shot.lorcanchinnock.com/docs/removing-shot/). If you installed Shot with Homebrew before, it keeps updating itself, and `brew uninstall --zap shot` still removes it.

## Quick start

Shot lives in the menu bar. It takes over the macOS screenshot keys while it runs, and gives them back when it quits:

| Press | To |
|---|---|
| ⌘⇧4 | Take a screenshot. Press Tab to pick an area, a window or the whole screen. |
| ⌘⇧5 | Record. Press Tab to pick an area, a window or the whole screen. |

To keep the macOS screenshot tool, and for every other shortcut, see [Keyboard shortcuts](https://shot.lorcanchinnock.com/docs/keyboard-shortcuts/).

## Documentation

The [user guide](https://shot.lorcanchinnock.com/docs/) covers every feature, shortcut and setting:

- [Get started](https://shot.lorcanchinnock.com/docs/get-started/) and [Take a screenshot](https://shot.lorcanchinnock.com/docs/take-a-screenshot/)
- [Annotate a screenshot](https://shot.lorcanchinnock.com/docs/annotate-a-screenshot/) and [style it](https://shot.lorcanchinnock.com/docs/style-a-screenshot/)
- [Record your screen](https://shot.lorcanchinnock.com/docs/record-your-screen/), [edit the recording](https://shot.lorcanchinnock.com/docs/edit-a-recording/) and [export a GIF](https://shot.lorcanchinnock.com/docs/export-a-video-or-gif/)
- [Share a capture with an AI assistant](https://shot.lorcanchinnock.com/docs/share-a-capture-with-an-ai-assistant/)
- [Automation reference](https://shot.lorcanchinnock.com/docs/automation-reference/): the `shot://` URL scheme, for scripts and launchers
- [Troubleshooting](https://shot.lorcanchinnock.com/docs/troubleshooting/)

Shot is in English, German, French, Spanish, Italian, Brazilian Portuguese, Japanese, Korean and Simplified Chinese, and follows your Mac's language.

## Privacy

Shot collects nothing. It has no account, no cloud and no analytics, and it only goes online to check for updates, after you agree. See [Privacy](https://shot.lorcanchinnock.com/docs/privacy/).

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to build Shot from source, run the tests and send a change. To report a security problem, see [SECURITY.md](SECURITY.md).

## Support

Shot is free, with no ads. [Sponsoring](https://github.com/sponsors/LorcanChinnock) keeps it that way.

## License

Shot is free software under the [GNU General Public License v3.0](LICENSE).

## Acknowledgements

Shot updates itself with [Sparkle](https://sparkle-project.org), under the MIT license. See [Acknowledgements](Resources/Acknowledgements.txt).
