# First launch

![The welcome window's second step, Make it yours: Use Shot for ⌘⇧3 to ⌘⇧5 and Open Shot at login both on, with Agents and Continue buttons](../../../docs/media/welcome.png)

The first time you open Shot, a welcome window takes about 30 seconds, in three steps. Close it at any step to skip the rest.

1. **Screen Recording access.** macOS requires it for every capture. Click **Grant**, or **Open System Settings**, and turn on Shot under **Screen & System Audio Recording**. Once you've been to System Settings, the window asks you to **Relaunch**, since macOS applies access only after a relaunch. Then the window carries on. If Shot already has access, this step is skipped.
2. **Make it yours.** **Use Shot for ⌘⇧3 to ⌘⇧5** is on: macOS's own screenshot shortcuts turn off while Shot runs, and come back when it quits. Turn it off to keep them, and Shot uses ⌃⇧3, ⌃⇧4 and ⌃⇧5 instead. **Open Shot at login** is ticked, so your shortcuts work after a restart. **Continue** applies both. If you close the window here instead, macOS keeps its shortcuts and Shot isn't added to your login items. The **Agents** button opens [Settings › Agents](#using-shot-with-ai-agents), for Claude Code, Codex or Cursor.
3. **Try it.** Press your area shortcut and drag out any area. Once the capture is done, the window comes back with a few tips, and **Done** closes it. **Skip** closes it before you capture.

If you used Shot before the welcome window existed, you won't see it. To open it again, use [`shot://welcome`](#url-scheme); opened that way, it starts from your current settings and closing it changes nothing. If Shot loses its Screen Recording access later, a capture opens the window at the access step.
