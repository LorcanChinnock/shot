---
title: Take a screenshot
summary: "Capture an area, a window, the whole screen or a long page, use a timer, or copy the text off your screen."
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

## Capture a long page

Capture Scrolling Area takes one screenshot of something taller or wider than the screen: a long web page, a chat thread, a document, a settings list or a spreadsheet. You scroll, and Shot builds the picture as you go. Shot never scrolls for you, so it works in every app and needs no extra permissions.

1. Choose **Capture Scrolling Area** in Shot's menu bar menu, or press the shortcut you gave it in **Settings › Shortcuts**.
2. Drag across the part of the screen that scrolls, or press <kbd>Space</kbd> and click a window. A panel appears beside it.
3. Scroll the content with the trackpad, the mouse wheel, <kbd>Page Down</kbd> or <kbd>Space</kbd>. Any direction works, and so does scrolling back. The panel's preview shows the picture so far, with the parts you haven't scrolled over hatched, so you can go back and fill them in.
4. Press <kbd>Return</kbd> or click **Done**. The screenshot is copied and saved like any other. <kbd>Esc</kbd> cancels and keeps nothing.

Sticky headers, footers, pinned columns and floating buttons appear once, where they belong. If the panel says something needs attention, it tells you what to do: scroll back a little after a big jump, pause a video that's playing in the area, or include some text so there's something to line up. The picture can be up to 30,000 pixels on a side.

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

## Without a mouse

After <kbd>⌘⇧4</kbd>, press an arrow key to start an area at the pointer, or in the middle of the screen. Then:

- Arrow keys move the area by 10 points, or by 1 with <kbd>Shift</kbd>.
- <kbd>⌥</kbd> with the arrow keys resizes it.
- <kbd>Tab</kbd> still sets the ratio, and <kbd>Return</kbd> captures.

To pick a window, press <kbd>Space</kbd>, step through the windows with <kbd>Tab</kbd> and <kbd>⇧Tab</kbd>, and press <kbd>Return</kbd>. VoiceOver reads out the size and the window's name as you go.

## Choose what happens after a capture

In **Settings › Capture**, choose whether Shot saves each screenshot, copies it and shows Quick Access, or opens it in the [annotation editor](#annotate-a-screenshot) straight away.

> [!NOTE]
> Every action here also has a [`shot://` link](#url-scheme), such as `shot://capture-timer?seconds=5`, `shot://capture-scrolling`, `shot://capture-previous` and `shot://copy-text`, for scripts and launchers.
