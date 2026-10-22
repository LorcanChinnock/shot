---
title: Use your own AI provider
summary: "Send a capture to Ollama, LM Studio, OpenAI, Gemini or OpenRouter when you ask for alt text, and see what leaves your Mac."
group: AI agents
---

**Copy Alt Text** describes a screenshot in a sentence or two. On macOS 27 it uses Apple's model on your Mac, which needs no setup. If your Mac is older, or you want a bigger model, you can point Shot at a service you choose instead.

It's off until you turn it on, and Shot never signs in to an AI account for you.

## Set it up

1. Open **Settings › Agents** and turn on **Use my own AI provider**.
2. Choose a **Service**. **Ollama** and **LM Studio** are listed first, since they run on your Mac. **OpenAI**, **Gemini** and **OpenRouter** run on the internet. **Custom** takes any address that follows the OpenAI format.
3. Check the **Address** and **Model**. Choose a model that can read images, such as `qwen2.5vl` on Ollama.
4. For an online service, paste your **Key**. Shot keeps it in your Keychain, not in a file. Local services don't need one.

## Use it

Right-click a screenshot and choose **Copy Alt Text**. Shot sends the image to your service, copies the answer and shows a toast. With the setting on, the item shows on any macOS, not only 27.

## What leaves your Mac

- Only the screenshot you chose, and only when you choose **Copy Alt Text**. Nothing is sent when you take a capture.
- The image is scaled to 2000 pixels on its longest side and sent as a JPEG under 5 MB, with a short instruction. Your marks and file names aren't sent.
- A local service keeps all of it on your Mac. An online service gets the image under its own terms, so blur private details first.

> [!NOTE]
> Shot checks every answer before it copies it. If a model replies in the wrong shape, you get an error and nothing is copied. Small local models do this more often than large ones.
