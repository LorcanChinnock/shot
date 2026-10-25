---
title: Share a capture with an AI assistant
summary: "Paste a marked-up screenshot into Claude or ChatGPT, or connect Shot so an assistant can fetch your captures itself."
group: AI agents
---

AI assistants like Claude and ChatGPT take a pasted screenshot, and your arrows and boxes show them where to look. Shot can go further: it can hand an assistant the file itself, tell it exactly what you marked, and let it fetch your captures when you ask.

## Paste a marked-up screenshot

1. Take a screenshot and mark it up: circle the bug, add an arrow or a note.
2. Paste it into Claude, ChatGPT or any other assistant.

That's all most people need. Your marks show the assistant where to look.

## Give the assistant the file

Right-click a Quick Access card and choose **Copy Path**, or give **Copy Latest Capture's Path** a shortcut in **Settings › Shortcuts**. An assistant that can open files can read the image from its path, now or later in the conversation. Copies are always the image alone.

## Let the assistant fetch your captures

Connect Shot to your assistant once, and you can ask "what did I mark in my latest screenshot?" without pasting anything.

![Settings › Agents with Hand captures to agents, Let agents capture and record, and Send to Agent turned on, Send to Agent set to open Claude Code in Terminal, the shot command installed, and the MCP server's setup for Claude and Claude Code](../../../docs/media/agents-settings.png)

1. Open **Settings › Agents**. Every switch there starts off.
2. On the **MCP server** card (the connection that lets an assistant use Shot), click **Install** beside your assistant. It lists the ones it finds on your Mac. The row then shows **Installed**.
3. Restart the assistant if Shot asks you to. Claude only reads its setup when it opens.
4. Optionally, turn on **Hand captures to agents**, so Shot records inside each screenshot which app and window it came from and what you marked. The assistant sees the image either way, but with this on it also knows what each mark points at. See [Hand captures to agents](#hand-captures-to-agents).

> [!NOTE]
> ChatGPT isn't on the list. It only connects to tools on the internet, and Shot's runs on your Mac. You can still paste screenshots into it.

## What a connected assistant can do

- **Read your captures:** your latest one, or one it finds by name or by the text in it, with what you marked and what you said while recording.
- **Wait for your next capture,** or ask you to select something on screen.
- **Edit them** as you would in the editors, with every layer still live: crop, pad, style, mark up and combine screenshots, or cut, speed up, mark up and shrink recordings.
- **Hide private text,** such as emails and card numbers.
- **Compare two screenshots** to see what changed.
- **Take its own** screenshot or recording of a window, if you allow it. See [Let an agent capture and record](#let-an-agent-capture-and-record).

Anything an assistant makes shows a small mark in the [gallery](#see-what-agents-made).

> [!WARNING]
> Shot sends nothing anywhere. But whatever an assistant reads goes to that assistant's provider, so blur or pixelate anything private first, as in [Annotate a screenshot](#annotate-a-screenshot). A connected assistant can also hide private text such as emails and card numbers for you, but only the ones it can read, so check the result before you share it.

## Using a coding agent?

Claude Code, Codex and Cursor can also take a marked-up capture as a task, and capture the iOS Simulator to check their own work. See [Work with coding agents](#work-with-coding-agents).
