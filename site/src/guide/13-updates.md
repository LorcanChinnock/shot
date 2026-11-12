---
title: Updates
summary: "How Shot keeps itself up to date."
group: Help
---

Shot updates itself through [Sparkle](https://sparkle-project.org), once you allow it to check.

## Turn on automatic updates

The second time you open Shot, it asks whether to check for updates automatically. If you say yes, Shot asks GitHub once a day whether a new version is out, and installs it when you agree.

To change your mind, turn **Check automatically** on or off in **Settings › About**.

## Check now

Click **Check for Updates** in **Settings › About**, or choose **Check for Updates…** in Shot's menu bar menu. A small window says Shot is looking for a new version, with **Cancel**. When a check finds a new version, that menu item becomes **Update to Shot** and the version. When an automatic check finds one, a dot also takes the place of the top-right corner of Shot's menu bar icon until you open the update.

The top of **Settings › About** shows Shot's version and what the last check found. It says **Up to date** only when a check since Shot opened found nothing, names the new version once one is out, and otherwise says when Shot last checked.

## Installing an update

When there's a new version, Shot opens a small window with what's new in it. Click **Install and Relaunch** to download it, with a progress bar and Cancel. Shot then quits, installs it and opens again, and it asks about unsaved edits and saves any recording first.

- **Later** closes the window, and the next check offers the version again. Closing the window or pressing Esc does the same. Later only shows while **Check automatically** is on, since otherwise there's no next check.
- **Skip** stops Shot offering that version. A newer one is still offered.
- **Install future updates automatically**, shown while Check automatically is on, lets Shot download each new version by itself and install it the next time Shot quits.

An update an automatic check finds doesn't take over the keyboard while you work, and its window can open behind other windows. Choose **Update to Shot** in the menu bar menu to bring it back.

## Installing over a running copy

If you ran the install command again, or Homebrew replaced Shot, while Shot was running, a check offers to relaunch it instead of updating.

> [!NOTE]
> Every release is signed with the same certificate, so macOS keeps Shot's Screen Recording access after an update. If you installed Shot before it could update itself, macOS asks for that access once more after your next install.
