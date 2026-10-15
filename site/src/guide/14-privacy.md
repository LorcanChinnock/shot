---
title: Privacy
summary: "What Shot collects (nothing) and the one time it goes online."
group: Help
---

## What Shot sends

Nothing. Shot collects no analytics, and the only time it connects to the network is to [check for updates](#updates), after you agree to it. The GitHub links in **Settings › About**, including Sponsor, open in your browser.

## Where your captures go

Captures go to the folder you choose in **Settings › General**, `~/Pictures/Shot` by default. When saving is off, they go to a temporary folder, and Shot deletes ones older than a day when it launches.

Text search, editor layers and video projects stay in Shot's own Application Support folder on your Mac, never inside the files you share.

## What agents can do

An agent can take a screenshot or recording through Shot only while **Let agents capture and record** is on, and it starts off.

- Shot shows a notice each time.
- An agent's recording always shows the region border and the controls to stop it.
- It never records the microphone or camera, and it records system audio only if **Settings › Recording** has it on.

> [!WARNING]
> Whatever an agent reads goes to that agent's model provider. See [Use Shot with AI agents](#use-shot-with-ai-agents) for how to hide private text first.

## Permissions

Shot needs **Screen & System Audio Recording** access for every capture. macOS asks for **Microphone** and **Camera** access only when Shot first uses them: when you record with them, or try them with **Test** or **Preview** in **Settings › Recording**.

To give Shot every permission at once, click **Grant** beside each one in **Settings › About**. Once macOS has asked, the button becomes **Open**, which goes to that list in System Settings.
