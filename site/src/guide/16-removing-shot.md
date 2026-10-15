# Removing Shot

Quit Shot and move it to the Trash. Quitting gives the screenshot keys back to macOS. If ⌘⇧3 to ⌘⇧5 still do nothing, for example because Shot crashed before you removed it, turn the shortcuts back on in **System Settings › Keyboard › Keyboard Shortcuts › Screenshots**.

To remove everything else Shot keeps:

- **Login item:** turn off **Open Shot at login** in **Settings › General** before you quit, or remove Shot in **System Settings › General › Login Items & Extensions**.
- **Settings:** run `defaults delete dev.lorcan.Shot`, which removes `~/Library/Preferences/dev.lorcan.Shot.plist`.
- **Agent socket:** delete `~/Library/Application Support/dev.lorcan.Shot`.
- **Caches:** delete `~/Library/Caches/dev.lorcan.Shot`, which holds update downloads and cached update checks.
- **Temporary files:** run `rm -rf "$TMPDIR/Shot"` to remove captures taken with saving off and leftover recording pieces. macOS also clears this folder on its own over time.
- **Permissions:** run `tccutil reset All dev.lorcan.Shot` to clear every permission you gave Shot.
- **`shot` command:** click **Uninstall** beside **shot command** in **Settings › Agents** before you quit, or run `sudo rm /usr/local/bin/shot`. `brew uninstall shot` removes Homebrew's.
- **AI agents:** remove the MCP server from each agent you added it to: `claude mcp remove shot` for Claude Code, the `shot` entry under `mcpServers` for Cursor, and `[mcp_servers.shot]` in `~/.codex/config.toml` for Codex.

Your captures stay in your save folder until you delete them.
