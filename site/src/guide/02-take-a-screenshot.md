---
title: Take a screenshot
summary: "Capture an area, a window or the whole screen, use a timer, or copy the text off your screen."
group: Capture
---

![Dragging out an area with the magnifier, then the Quick Access card sliding into the corner and showing its buttons](../../../docs/media/capture.gif)

Every screenshot is saved, copied to the clipboard as a PNG, and shown in a [Quick Access](#quick-access) card, so you can paste it straight away.

## Capture an area

1. Press <kbd>⌘⇧4</kbd>. The screen freezes.
2. Drag across what you want. A magnifier by the pointer helps you line up exact edges, and a label shows the size in pixels.
3. Let go.

While you drag:

| Press | To |
|---|---|
| <kbd>Shift</kbd> | Keep the area square. |
| <kbd>Tab</kbd> | Step through 1:1, 4:3, 3:2 and 16:9, then back to free. <kbd>⇧Tab</kbd> steps back. The way you start dragging picks landscape or portrait. |
| <kbd>X</kbd> | Turn the ratio between landscape and portrait. |
| <kbd>Space</kbd> | Hold it to move the whole area. |
| <kbd>Esc</kbd> | Cancel. |

## Capture a window

1. Press <kbd>⌘⇧4</kbd>, then <kbd>Space</kbd>.
2. Click the window.

Shot captures the window as it is right now, even if something covers it, and keeps its macOS shadow. To leave the shadow out, turn off **Window shadow** in **Settings › Capture**.

## Capture the whole screen

Press <kbd>⌘⇧3</kbd>. Shot captures the screen the pointer is on.

## Use a timer

Need to open a menu or hover over something first? Choose **Capture Full Screen After Delay** in Shot's menu bar menu. Shot counts down on screen for 3 or 5 seconds, the same as your recording countdown, then captures the screen under the pointer. Shot's menu bar icon shows the seconds left too.

Shot stays in the background while it counts, so the menu you open stays open. Press <kbd>Esc</kbd> or click **Cancel** to stop.

## Capture the same area again

**Capture Previous Area** in the menu bar menu takes the same area as your last area screenshot, with no dragging. It's handy for a before-and-after pair that lines up exactly.

> [!TIP]
> It has no shortcut until you give it one in **Settings › Shortcuts**. Shot forgets the area when it quits.

## Copy text from the screen

Copy Text reads the text in part of the screen and copies it, without saving a screenshot. Everything happens on your Mac.

1. Give **Copy Text** a shortcut in **Settings › Shortcuts**, then press it.
2. Drag across the text, or press <kbd>Space</kbd> and click a window.
3. Paste the text wherever you like.

To copy the text from a screenshot you already took, right-click its Quick Access card or its tile in the [gallery](#find-your-captures) and choose **Copy Text**.

## Capture a long page

Capture Scrolling Area joins a web page, chat thread, document or spreadsheet that is bigger than your screen into one image. You scroll, in any direction and as many directions as you like, and Shot works out how the content moved.

1. Choose **Capture Scrolling Area** from Shot's menu bar menu, or give it a shortcut in **Settings › Shortcuts**.
2. Drag out the part of the screen that scrolls. A sticky header, footer or first column can be inside it.
3. Scroll the content with your trackpad, mouse wheel or <kbd>Page Down</kbd>. Go down, sideways or both, so a wide spreadsheet can be captured top to bottom and left to right in one image. The panel beside the area shows the size so far and the newest part.
4. Press <kbd>Return</kbd> to finish. The image is copied and saved like any other capture. <kbd>Esc</kbd> cancels.

Shot keeps only what it hasn't seen yet. A sticky header, footer or floating button appears once, and scrolling back over what you've captured adds nothing. The image can reach 30,000 pixels along a side.

Shot tells you in the panel when it can't carry on, and the outline turns red:

- **Scrolled too far at once:** scroll back a little and carry on.
- **Something keeps changing:** a playing video or animation can't be lined up, so pause it or scroll past it.
- **Not enough to line up:** an area that is blank, or repeats the same thing, gives Shot nothing to follow. Include some text or an image.

Scrolling by hand asks for no permission beyond the Screen Recording one every capture needs.

## Without a mouse

After <kbd>⌘⇧4</kbd>, press an arrow key to start an area at the pointer, or in the middle of the screen. Then:

- Arrow keys move the area by 10 points, or by 1 with <kbd>Shift</kbd>.
- <kbd>⌥</kbd> with the arrow keys resizes it.
- <kbd>Tab</kbd> still sets the ratio, and <kbd>Return</kbd> captures.

To pick a window, press <kbd>Space</kbd>, step through the windows with <kbd>Tab</kbd> and <kbd>⇧Tab</kbd>, and press <kbd>Return</kbd>. VoiceOver reads out the size and the window's name as you go.

## Choose what happens after a capture

In **Settings › Capture**, choose whether Shot saves each screenshot, copies it and shows Quick Access, or opens it in the [annotation editor](#annotate-a-screenshot) straight away.

> [!NOTE]
> Every action here also has a [`shot://` link](#url-scheme), such as `shot://capture-timer?seconds=5`, `shot://capture-previous`, `shot://capture-scrolling` and `shot://copy-text`, for scripts and launchers.
