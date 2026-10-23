---
title: Use your own AI provider
summary: "Send a capture to Ollama, LM Studio, OpenAI, Gemini, OpenRouter or Anthropic (Claude) when you ask for alt text, and see what leaves your Mac."
group: AI agents
---

**Copy Alt Text** describes a screenshot in a sentence or two. On macOS 27 it uses Apple's model on your Mac, which needs no setup. If your Mac is older, or you want a bigger model, you can point Shot at a service you choose instead.

It's off until you turn it on, and Shot never signs in to an AI account for you.

## Set it up

1. Open **Settings › Agents** and turn on **Use my own AI provider**.
2. Choose a **Service**. **Ollama** and **LM Studio** are listed first, since they run on your Mac. **OpenAI**, **Gemini**, **OpenRouter** and **Anthropic** run on the internet. **Anthropic** is for Claude with an API key from the Anthropic Console; a Claude.ai chat subscription can't be used, since Anthropic doesn't allow other apps to sign in with it. **Custom** takes any address, and shows a **Format** choice: **OpenAI-compatible** for most services, or **Anthropic Messages** for one that speaks Claude's format.
3. Check the **Address** and **Model**. Choose a model that can read images, such as `gemma3` on Ollama.
4. For an online service, paste your **Key**. Shot keeps it in your Keychain, not in a file. Local services don't need one.

## Use it

Right-click a screenshot and choose **Copy Alt Text**. Shot sends the image to your service, copies the answer and shows a toast. With the setting on, the item shows on any macOS, not only 27.

**Copy Bug Report** uses the same service. For a recording it sends up to eight frames, the text read from them and the words you said, which Shot transcribes on your Mac first. If the model's context is too small for that many frames, Shot tries again with half as many, down to one.

## What leaves your Mac

- Only the capture you chose, and only when you choose **Copy Alt Text** or **Copy Bug Report**. Nothing is sent when you take a capture.
- The image is scaled to 2000 pixels on its longest side and sent as a JPEG under 5 MB (an Anthropic request is also kept under 32 MB in all), with a short instruction. Anything you've drawn on it is part of the image. Its file name isn't sent.
- A local service keeps all of it on your Mac. An online service gets the image under its own terms, so blur private details first.

> [!TIP]
> On Ollama, `gemma3` was the quickest model we tried. It answered in about seven seconds for alt text, and 10 to 25 seconds for a bug report, though its bug reports often ignored what was said in a recording. `qwen2.5vl` took about three times as long, followed a recording more closely, but added steps nobody had done. `llama3.2-vision` didn't load at all on the Ollama version we tested. Large screenshots can overflow Ollama's default context length, which shows as an error. Raise **Context length** to 8192 in Ollama's settings if you see one.

> [!NOTE]
> Shot checks every answer before it copies it. If a model replies in the wrong shape, you get an error and nothing is copied. Small local models do this more often than large ones.
>
> Local models also misread text. In our tests the best one got about three quarters of the lines of text in a screenshot exactly right, so don't rely on alt text to copy text exactly.
