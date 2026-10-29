---
title: Take a screenshot
summary: "Capture an area, a window or the whole screen, wait a few seconds first, or copy the text off your screen."
group: Capture
---

![Pressing Tab to step the capture between an area, a window and the full screen, dragging out an area with the magnifier, then the Quick Access card sliding into the corner and showing its buttons](../../../docs/media/capture.gif)

Every screenshot is saved, copied to the clipboard as a PNG, and shown in a [Quick Access](#quick-access) card, so you can paste it straight away.

## Take a screenshot

1. Press <kbd>⌘⇧4</kbd>, or choose **Screenshot** in the menu bar menu. The screen freezes.
2. Drag across what you want. A magnifier by the pointer helps you line up exact edges, and a label shows the size in pixels.
3. Let go.

Chips at the top of the screen show what you are about to capture: **Area**, **Window** or **Full Screen**. Press <kbd>Tab</kbd> to move to the next one (<kbd>⇧Tab</kbd> goes back), or click a chip.

- **Area:** drag across it.
- **Window:** click a window. Shot captures it as it is right now, even if something covers it, and keeps its macOS shadow. To leave the shadow out, turn off **Window shadow** in **Settings › Capture**.
- **Full Screen:** click the screen you want, or press <kbd>Return</kbd>. With more than one display, the one under the pointer is highlighted.

While you drag an area:

| Press | To |
|---|---|
| <kbd>Shift</kbd> | Keep the area square. |
| <kbd>R</kbd> | Step through 1:1, 4:3, 3:2 and 16:9, then back to free. <kbd>⇧R</kbd> steps back. The way you start dragging picks landscape or portrait. |
| <kbd>X</kbd> | Turn the ratio between landscape and portrait. |
| <kbd>Space</kbd> | Hold it to move the whole area. |
| <kbd>Esc</kbd> | Cancel. |

## Wait before the screenshot

Need to open a menu or hover over something first? Click the **Delay** chip, or press <kbd>D</kbd>, to step through Off, 3, 5 and 10 seconds. Then pick the area, window or screen as usual. Shot counts down on screen and captures what is there when the time is up. Shot's menu bar icon shows the seconds left too.

Shot stays in the background while it counts, so the menu you open stays open. Press <kbd>Esc</kbd> or click **Cancel** to stop. The delay is back to Off the next time you take a screenshot.

## Copy text from the screen

Copy Text reads the text in part of the screen and copies it, without saving a screenshot. Everything happens on your Mac.

1. Give **Copy Text** a shortcut in **Settings › Shortcuts**, then press it.
2. Drag across the text, or press <kbd>Tab</kbd> and click a window.
3. Paste the text wherever you like.

To copy the text from a screenshot you already took, right-click its Quick Access card or its tile in the [gallery](#find-your-captures) and choose **Copy Text**.

## Without a mouse

After <kbd>⌘⇧4</kbd>, press an arrow key to start an area at the pointer, or in the middle of the screen. Then:

- Arrow keys move the area by 10 points, or by 1 with <kbd>Shift</kbd>.
- <kbd>⌥</kbd> with the arrow keys resizes it.
- <kbd>R</kbd> sets the ratio, and <kbd>Return</kbd> captures.

To pick a window, press <kbd>Tab</kbd>, step through the windows with the arrow keys, and press <kbd>Return</kbd>. VoiceOver reads out the size and the window's name as you go.

## Choose what happens after a capture

In **Settings › Capture**, choose whether Shot saves each screenshot, copies it and shows Quick Access, or opens it in the [annotation editor](#annotate-a-screenshot) straight away.

> [!NOTE]
> Every action here also has a [`shot://` link](#url-scheme), such as `shot://capture-window` and `shot://copy-text`, for scripts and launchers.
