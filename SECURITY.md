# Security

Shot has access to your screen, and optionally your microphone and camera. It also updates itself, takes `shot://` URLs. If you find a way to misuse any of that, please tell me privately first.

## Reporting a vulnerability

Use GitHub's private reporting: open the repository's [Security tab](https://github.com/LorcanChinnock/shot/security) and choose **Report a vulnerability**. Please don't open a public issue or pull request for it.

Include what you found, the Shot version (**Settings › About**), your macOS version, and the steps to reproduce it. A short proof of concept helps.

Please give me reasonable time to fix it before you share it more widely. I'll credit you in the release notes if you want.

## Supported versions

Only the latest release gets security fixes. Shot updates itself, and running the install command from the website again installs the same release.

## What counts

- Captures, recordings or the camera or microphone reaching something you didn't ask for.
- A `shot://` URL or a file Shot opens doing more than it should.
- The update path installing something that wasn't signed by the project.
- A file or setting being overwritten or deleted without you asking.

Bugs without a security impact belong in a [regular issue](https://github.com/LorcanChinnock/shot/issues/new/choose).
