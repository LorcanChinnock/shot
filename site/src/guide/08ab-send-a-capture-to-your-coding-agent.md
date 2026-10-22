---
title: Send a capture to your coding agent
summary: "Open Claude Code, Codex or Cursor in a terminal with your screenshot and what you marked on it, as a task."
group: AI agents
---

You mark up a screenshot because something's wrong: an arrow at a button and a note saying "this should be bold". **Send to Agent** turns that into a task. It opens your coding agent in a terminal, in the project folder you choose, with the screenshot and a short summary of your marks, so you don't paste the image and retype what your marks already say.

The agent runs on your own account, as if you'd started it yourself. Shot needs no key or sign-in, and sends nothing until you choose **Send to Agent**.

## Set it up

1. Open **Settings › Agents** and turn on **Send to Agent**.
2. Choose your agent: **Claude Code**, **Codex**, **Cursor** or **Custom**. Shot finds the agent's command on your Mac and shows where it is. If it says it couldn't find it, install the agent, then open Settings again.
3. Choose the terminal it opens in: Terminal, iTerm, Ghostty or Warp. Shot lists the ones you have.
4. Choose the **working folder**, usually your project. The agent starts there and works on what's in it.

## Send a capture

1. Take a screenshot and mark it up. Add a note with what you want done, such as "make this 8pt from the edge".
2. Right-click its Quick Access card, or its tile in the gallery, and choose **Send to Claude Code** (or your agent's name). In the editor, it's in the **File** menu.
3. A terminal window opens with the agent running and your task in it. When the agent finishes, the window stays open in your working folder.

From the editor, Shot saves your changes first, so the agent gets the version with your marks. It always gets the saved file with the marks drawn on, never the original under a blur.

> [!TIP]
> Send to Agent has no shortcut until you give it one. It never runs on its own, and it doesn't change what happens when you take a screenshot.

## What the agent gets

Your notes come first, as the task. Then the file's path and a few lines about it:

```
Make "Open at login" bold
Screenshot from Shot: /Users/you/Pictures/Shot/Shot 2026-10-22 at 09.14.03.png
Open the image first; the user's marks are drawn on it.
Captured from Safari, window "Settings". 1664×1263 px, 1 pt = 2 px.
What the user marked (pixels, top-left origin):
- arrow from (900, 500) to (700, 300), red, pointing at "Open at login"
- rectangle at (560, 140), 160×45, yellow, around "General"
```

- Shot reads the text in the screenshot, on your Mac, to say what each arrow points at and what each box surrounds.
- Up to 10 marks are listed. Blurred and pixelated areas are counted, and their text is never quoted.
- With no notes, it starts with "Here's a screenshot I marked up:".
- The app, window and marks come from the record Shot keeps inside each screenshot, so they're there only with [Hand captures to agents](#hand-captures-to-agents) on. With it off, the agent gets the path and the "open the image first" line.
- If Shot's [MCP server](#the-mcp-server) is set up for the agent, the prompt tells it to call `find_text` for the rest of the text.

> [!NOTE]
> The agent sends what it reads to its model provider, the same as anything else you show it. Blur private details first.

## A custom agent

Choose **Custom** to run any command. Shot fills in:

- `{path}`: the screenshot
- `{dir}`: the folder it's in
- `{prompt}`: the task and summary above

For example, `gemini -i "@{path} {prompt}"`. If you leave `{prompt}` out, Shot adds it at the end. Use the placeholders bare or inside double quotes, not single quotes.

## How it works

Shot writes a small script, readable only by you, to its folder in Application Support, and opens it in your terminal. The script starts in your working folder, runs the agent with the prompt, then deletes itself and leaves a shell open. The prompt goes to the agent as it is, so quotes, `$` and new lines in your notes can't run as commands. Opening a script this way needs no permission to control your terminal.

To send from a script, or another app, use [`shot://send-to-agent?path=<file>`](#url-scheme). It works only while **Send to Agent** is on.
