---
title: Removing Shot
summary: "Uninstall Shot and clear everything it keeps."
group: Help
---

## Uninstall Shot

Paste this line into Terminal and press Return. It quits Shot and moves it to the Trash, and leaves your settings, your permissions and the saved versions of edited screenshots in place, so installing Shot again picks up where you left off:

```sh
curl -fsSL https://shot.lorcanchinnock.com/uninstall.sh | bash
```

To remove everything Shot keeps as well, use this line instead:

```sh
curl -fsSL https://shot.lorcanchinnock.com/uninstall.sh | bash -s -- --everything
```

That deletes the saved versions in Application Support, so screenshots you saved edits over can no longer be reverted. Your captures stay in your save folder either way.

To do it by hand, quit Shot (quitting gives the screenshot keys back to macOS) and move it to the Trash. If you installed it with Homebrew in the past, run `brew uninstall --zap shot` instead.

> [!TIP]
> If <kbd>⌘⇧4</kbd> and <kbd>⌘⇧5</kbd> still do nothing, for example because Shot crashed before you removed it, turn the shortcuts back on in **System Settings › Keyboard › Keyboard Shortcuts › Screenshots**.

## Remove everything else by hand

The `--everything` command above does all of this except the login item and the old `shot` command. It prints the `sudo rm` line for that command but doesn't run it, and it doesn't touch any AI app's settings.

- **Login item:** turn off **Open Shot at login** in **Settings › General** before you quit, or remove Shot in **System Settings › General › Login Items & Extensions**.
- **Settings:** run `defaults delete dev.lorcan.Shot`, which removes `~/Library/Preferences/dev.lorcan.Shot.plist`.
- **Application Support:** delete `~/Library/Application Support/dev.lorcan.Shot`. It holds the layers of saved versions and video projects, the originals of screenshots you saved edits over, and the text Shot read for search. Delete it and those screenshots keep their edits but can no longer be reverted.
- **Caches:** delete `~/Library/Caches/dev.lorcan.Shot`, which holds update downloads and cached update checks.
- **Temporary files:** run `rm -rf "$TMPDIR/Shot"` to remove captures taken with saving off and leftover recording pieces. macOS also clears this folder on its own over time.
- **Permissions:** run `tccutil reset All dev.lorcan.Shot` to clear every permission you gave Shot.
- **The `shot` command:** older versions of Shot could install one. If `/usr/local/bin/shot` is still there, run `sudo rm /usr/local/bin/shot`, and delete any `shot` entry you added to an AI app's MCP settings.
