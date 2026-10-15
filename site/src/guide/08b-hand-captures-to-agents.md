---
title: Hand captures to agents
summary: "Record inside each screenshot where it came from and what you marked, so an agent can read it."
group: AI agents
---

## Turn it on

Turn on **Hand captures to agents** in **Settings › Agents**. Shot then records, inside each screenshot you take or save from the editor, which app and window it came from and what you marked. Agents read it through the [MCP server](#the-mcp-server) or `shot info`.

- A copied capture is also kept as a file, even with **Save to folder** off, so the agent can fetch it. With saving off, that file stays in a temporary folder for about a day: Shot deletes older ones when it launches.
- With the setting off, Shot records nothing.
- Recordings have no record.

> [!NOTE]
> Window titles can be private, which is one reason this is off until you turn it on.

## The capture record

The record is stored in the image's own metadata, as JSON in the XMP property `shot:record` (namespace `https://shot.lorcanchinnock.com/ns/capture/1.0/`), so there's no extra file in your capture folder and it goes wherever the file goes. A copy of a PNG capture keeps it too, but a copy of a JPEG capture or of a styled capture doesn't, since those are new PNGs. It follows the `shot.capture/2` schema:

```json
{
  "schema": "shot.capture/2",
  "original": "Shot 2026-10-10 at 14.03.12.png",
  "kind": "image",
  "created": "2026-10-10T14:03:12Z",
  "size": { "width": 2880, "height": 1800 },
  "scale": 2,
  "source": {
    "mode": "window",
    "app": "Simulator", "bundleID": "com.apple.iphonesimulator",
    "windowTitle": "iPhone 17 Pro",
    "screenFrame": { "x": 120, "y": 80, "width": 1440, "height": 900 }
  },
  "canvas": [0, 0, 2880, 1800],
  "coordinateSpace": "image pixels, top-left origin",
  "annotations": [
    { "id": "…", "type": "arrow", "from": [410, 220], "to": [612, 388], "color": "red", "hex": "#FF3B30", "lineWidth": 4 },
    { "id": "…", "type": "rectangle", "rect": [560, 340, 220, 96], "color": "red", "hex": "#FF3B30", "lineWidth": 4 },
    { "id": "…", "type": "text", "text": "too tight here", "rect": [600, 450, 180, 32], "color": "red", "hex": "#FF3B30", "fontSize": 24 },
    { "id": "…", "type": "counter", "number": 1, "center": [300, 120], "color": "red", "hex": "#FF3B30", "lineWidth": 4 },
    { "id": "…", "type": "blur", "rect": [40, 40, 300, 30], "note": "redacted, content hidden", "amount": 0.008 }
  ]
}
```

- `original` is set on a version saved from the editor, and names the file it was saved from, in the same folder. `canvas` is the part of that file the version shows, in its pixels: a crop, or past its edges where you added padding. `crop` is there when the version is a crop of it, in the same pixels, and Shot reopens the version with that crop still adjustable. `editable` is `true` when the marks rebuild every layer exactly, and Shot then reopens the version as `original` with the marks live.
- `source.mode` is `area`, `window` or `fullscreen`. A window capture names the app and its window; an area or full screen capture names the frontmost app. `screenFrame` is in points, with the origin at the top left of the main display.
- Coordinates are pixels of the saved file, from its top left, so a crop or padding and **Scale Retina captures to 1×** are already applied. `rect` is `[x, y, width, height]`; `from`, `to` and `center` are `[x, y]`; a pen or marker stroke's `points` are `[[x, y], …]`.
- `type` is one of `arrow`, `line`, `rectangle`, `ellipse`, `triangle`, `diamond`, `star`, `highlight`, `text`, `note`, `counter`, `pen`, `marker`, `image`, `blur`, `pixelate` or `spotlight`; an agent that writes marks can still give `rounded`, which means a `rectangle` with the default `cornerRadius`. `color` is the nearest palette name, with the exact `hex` beside it. Text and notes give their `text`; a blur, pixelate, spotlight or placed image gives only where it is, never what's under it. Hidden layers are left out.
- `lineWidth`, `fill`, `fontSize`, `amount` (a blur's or pixelation's strength), `bend` and `cornerRadius` (a shape's rounded corners) are there so Shot can rebuild a mark; an agent can ignore them.
- `id` names the layer, and an [edit's](#editing-images) `remove` takes it. Marks an agent writes can leave it out.

> [!NOTE]
> Development builds before 0.7.0-beta.40 wrote this as a `.shot.json` file beside each capture instead. Nothing reads those any more, so you can delete them.
