---
title: Troubleshooting
summary: "Fixes for permissions, shortcuts and agents that don't work."
group: Help
---

## Captures fail after I turned on Screen Recording

macOS applies the access only after Shot relaunches.

1. Quit Shot and open it again.
2. Check **Settings › About**: it shows **GRANTED** or **MISSING** beside **Screen & System Audio Recording**. **Grant** asks for access, and once macOS has asked, **Open** goes to that list in System Settings.
3. If it still says MISSING, run this in Terminal, then open Shot and grant access again:

```sh
tccutil reset ScreenCapture dev.lorcan.Shot
```

## Microphone or Camera says NOT ASKED, but System Settings shows Shot allowed

The allowed entry belongs to a differently signed copy of Shot, such as one you built yourself. Clear it, then click **Grant** in **Settings › About**:

```sh
tccutil reset Microphone dev.lorcan.Shot
tccutil reset Camera dev.lorcan.Shot
```

## ⌘⇧4 still opens the macOS screenshot tool

Shot takes over <kbd>⌘⇧3</kbd> to <kbd>⌘⇧5</kbd> only once it has Screen Recording access, and only while **Use Shot for ⌘⇧3 to ⌘⇧5** is on in **Settings › Shortcuts**.

- If you turned the macOS shortcuts back on in System Settings, turn that setting on again.
- A **Shortcut unavailable** message means another app already uses that shortcut. Pick another in **Settings › Shortcuts**.

## An agent can't see my captures, or can't capture or record

Run `shot doctor` from the terminal or editor the agent runs in. Without the `shot` command, run `/Applications/Shot.app/Contents/MacOS/shot-cli doctor`.

It checks:

- which copy of Shot answers (Shot or a ShotDev build) and its version,
- **Let agents capture and record**,
- the socket agents reach Shot on,
- Shot's Screen Recording access,
- whether macOS lets that terminal or editor read the capture folder.

It prints each check as JSON with a `fix` for anything that isn't passing, and exits with 1 if a check fails. It never opens Shot; it only asks a copy that's already running.

## Something else is wrong

Shot writes to the macOS log. Run this in Terminal while you try again:

```sh
log stream --predicate 'subsystem == "dev.lorcan.Shot"'
```

Then add what it prints to a bug report from **Settings › About**. File paths show as `<private>`.
