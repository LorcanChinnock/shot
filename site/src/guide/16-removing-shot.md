---
title: Removing Shot
summary: "Uninstall Shot and clear everything it keeps."
group: Help
---

## Uninstall Shot

1. Quit Shot. Quitting gives the screenshot keys back to macOS.
2. Move Shot to the Trash. If you installed it with Homebrew, run `brew uninstall --zap shot` instead.

Your captures stay in your save folder until you delete them.

> [!TIP]
> If <kbd>⌘⇧4</kbd> and <kbd>⌘⇧5</kbd> still do nothing, for example because Shot crashed before you removed it, turn the shortcuts back on in **System Settings › Keyboard › Keyboard Shortcuts › Screenshots**.

## Remove everything else

- **Login item:** turn off **Open Shot at login** in **Settings › General** before you quit, or remove Shot in **System Settings › General › Login Items & Extensions**.
- **Settings:** run `defaults delete dev.lorcan.Shot`, which removes `~/Library/Preferences/dev.lorcan.Shot.plist`.
- **Application Support:** delete `~/Library/Application Support/dev.lorcan.Shot`. It holds the layers of saved versions and video projects, the originals of screenshots you saved edits over, and the text Shot read for search. Delete it and those screenshots keep their edits but can no longer be reverted.
- **Caches:** delete `~/Library/Caches/dev.lorcan.Shot`, which holds update downloads and cached update checks.
- **Temporary files:** run `rm -rf "$TMPDIR/Shot"` to remove captures taken with saving off and leftover recording pieces. macOS also clears this folder on its own over time.
- **Permissions:** run `tccutil reset All dev.lorcan.Shot` to clear every permission you gave Shot.
- **The `shot` command:** older versions of Shot could install one. If `/usr/local/bin/shot` is still there, run `sudo rm /usr/local/bin/shot`, and delete any `shot` entry you added to an AI app's MCP settings.
