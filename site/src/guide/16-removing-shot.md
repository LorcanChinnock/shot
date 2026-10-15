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
> If <kbd>⌘⇧3</kbd> to <kbd>⌘⇧5</kbd> still do nothing, for example because Shot crashed before you removed it, turn the shortcuts back on in **System Settings › Keyboard › Keyboard Shortcuts › Screenshots**.

## Remove everything else

- **Login item:** turn off **Open Shot at login** in **Settings › General** before you quit, or remove Shot in **System Settings › General › Login Items & Extensions**.
- **Settings:** run `defaults delete dev.lorcan.Shot`, which removes `~/Library/Preferences/dev.lorcan.Shot.plist`.
- **Application Support:** delete `~/Library/Application Support/dev.lorcan.Shot`. It holds the agent socket, the layers of saved versions and video projects, recording marks, and the text Shot read for search.
- **Caches:** delete `~/Library/Caches/dev.lorcan.Shot`, which holds update downloads and cached update checks.
- **Temporary files:** run `rm -rf "$TMPDIR/Shot"` to remove captures taken with saving off and leftover recording pieces. macOS also clears this folder on its own over time.
- **Permissions:** run `tccutil reset All dev.lorcan.Shot` to clear every permission you gave Shot.
- **The `shot` command:** click **Uninstall** beside **shot command** in **Settings › Agents** before you quit, or run `sudo rm /usr/local/bin/shot`. `brew uninstall shot` removes Homebrew's.
- **AI agents:** remove the MCP server from each agent you added it to: `claude mcp remove shot` for Claude Code, `codex mcp remove shot` for Codex, and the `shot` entry under `mcpServers` in the config of Claude, Cursor and most other apps.
