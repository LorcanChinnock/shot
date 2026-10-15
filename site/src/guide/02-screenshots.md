# Screenshots

![Dragging out an area with the magnifier, then the Quick Access card sliding into the corner and showing its buttons](../../../docs/media/capture.gif)

Shot lives in the menu bar. Its menu lists every capture and recording action with its shortcut, plus **Open Gallery**, **Open Save Folder** and **User Guide**, which opens this guide online. While you record, it also has **Pause Recording** (**Resume Recording** while paused) and **Stop Recording**.

- **Area (⌘⇧4):** the screen freezes, and you drag out an area. A magnifier next to the pointer helps you find exact edges. Hold Shift for a square, or press Tab to step through 1:1, 4:3, 3:2, 16:9 and back to free (Shift-Tab steps back); the direction you start dragging picks landscape or portrait, and X rotates it mid-drag. Hold Space while dragging to move the area. A label by the pointer shows the size in pixels, and the ratio when one is set. Press Esc to cancel.
  - **Without a mouse:** press an arrow key to start an area at the pointer (or the screen centre), then arrows move it by 10 points (hold Shift for 1), ⌥ with arrows resizes it, Tab still sets the ratio, and Return captures it. In window mode, Tab and Shift-Tab step through the windows and Return captures the highlighted one. VoiceOver announces the size and the window name as you go.
- **Previous area:** **Capture Previous Area** in the menu bar menu, or [`shot://capture-previous`](#url-scheme), takes the area your last area screenshot took, without the overlay, so a before and after shot lines up exactly. It has no shortcut until you give it one in **Settings › Shortcuts**. Shot forgets the area when it quits, and says so if none was taken yet or that part of the screen is gone.
- **Window:** press Space after ⌘⇧4, then click a window. Shot keeps the macOS window shadow unless you turn it off in Settings › Capture.
- **Copy Text:** give **Copy Text** a shortcut in **Settings › Shortcuts**, or open [`shot://copy-text`](#url-scheme), then drag out an area (or press Space and click a window). Shot reads the text in it on your Mac and copies it, without saving a screenshot. To copy the text in a screenshot you already took, right-click its [Quick Access](#quick-access) card or its tile in the [gallery](#gallery) and choose **Copy Text**.
- **Full screen (⌘⇧3):** captures the screen under the pointer.
- **After a delay:** **Capture Full Screen After Delay** in the menu bar menu (3 or 5 seconds, as the recording countdown), or [`shot://capture-timer?seconds=5`](#url-scheme), counts down on screen, then captures the screen under the pointer. That gives you time to open a menu or hover over something first. Shot isn't activated while it counts, so the menu stays open. Press Esc or click **Cancel** to take nothing.

After a capture, Shot saves it, copies it, and shows it in [Quick Access](#quick-access). Choose which of these happen, or open the editor straight away, in **Settings › Capture**. Clipboard copies are always PNG.
