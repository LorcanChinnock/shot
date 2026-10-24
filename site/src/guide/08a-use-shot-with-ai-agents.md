---
title: Use Shot with AI agents
summary: "Hand your captures to Claude, ChatGPT or a coding agent, and let them capture and record for you."
group: AI agents
---

AI assistants like Claude and ChatGPT, and coding agents like Claude Code, Codex and Cursor, all take a pasted screenshot, and your arrows and boxes show them where to look. Shot can do more: hand over the file itself, tell the agent exactly what you marked, and let it fetch your captures, edit them, or take its own.

![Settings › Agents with Hand captures to agents, Let agents capture and record, and Send to Agent turned on, Send to Agent set to open Claude Code in Terminal, the shot command installed, and the MCP server's setup for Claude and Claude Code](../../../docs/media/agents-settings.png)

## Paste a marked-up screenshot

1. Take a screenshot and mark it up: circle the bug, add an arrow or a note.
2. Paste it into Claude, ChatGPT, Claude Code, Codex or Cursor.

That's all most people need. Your marks show the agent where to look.

## Give the agent the file

Right-click a Quick Access card and choose **Copy Path**, or give **Copy Latest Capture's Path** a shortcut in **Settings › Shortcuts**. An agent can open the file from its path, now or later in the conversation. Copies are always the image alone.

## Send it straight to your coding agent

Turn on **Send to Agent** in **Settings › Agents**, and a Quick Access card's menu gets **Send to Claude Code** (or Codex, Cursor, or a command of your own). It opens the agent in a terminal, in your project, with the screenshot and your marks as a task. See [Send a capture to your coding agent](#send-a-capture-to-your-coding-agent).

## Use your own AI provider

**Copy Alt Text** can use Ollama, LM Studio, OpenAI, Gemini, OpenRouter or Anthropic (Claude) instead of Apple's model. See [Use your own AI provider](#use-your-own-ai-provider).

## Set it up so the agent can ask Shot

Everything below is in **Settings › Agents**. Every switch there starts off.

1. **Turn on Hand captures to agents.** Shot then records, inside each screenshot, which app and window it came from and what you marked. See [Hand captures to agents](#hand-captures-to-agents).
2. **Add Shot's MCP server to your assistant or agent.** Settings › Agents lists the ones it finds on your Mac. Click **Install** beside yours. Then you can ask "what did I mark in my latest screenshot?" without pasting anything. See [The MCP server](#the-mcp-server).
3. **Install the `shot` command,** for agents and scripts that work in a shell. See [The shot command line](#the-shot-command-line).
4. **Optionally, turn on Let agents capture and record,** so an agent can screenshot or record a window, such as the iOS Simulator, to check its own work. See [Let an agent capture and record](#let-an-agent-capture-and-record).

## What an agent can do

- **Read your captures:** your latest one, or one it finds by name or by the text in it, with what you marked and what you said while recording.
- **Wait for your next capture,** or ask you to select something on screen.
- **Edit them** as you would in the editors, with every layer still live: crop, pad, style, mark up and combine screenshots, or cut, speed up, mark up and shrink recordings. See [Edit captures with JSON](#edit-captures-with-json).
- **Hide private text:** emails, tokens and card numbers.
- **Compare two screenshots** to see what changed.
- **Take its own** screenshot or recording of a window, if you allow it.

Anything an agent makes shows a small mark in the [gallery](#see-what-agents-made).

> [!WARNING]
> Shot sends nothing anywhere. But whatever an agent reads goes to that agent's model provider, so blur or pixelate anything private before you hand a capture over. `shot redact --detect` and the `redact` tool find emails, tokens and card numbers for you, but only the ones they can read, so check the result before you share it.
