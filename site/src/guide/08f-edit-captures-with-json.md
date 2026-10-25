---
title: Edit captures with JSON
summary: "Crop, pad, style and mark up a screenshot, or cut, speed up and shrink a recording, from one JSON edit."
group: AI agents
---

`shot edit` and the MCP server's `edit_image` and `edit_video` tools make the editors' changes from one JSON object, so an agent can do in one step what you'd do by hand. The result opens in Shot with every layer still live.

## Edit an image

The result is the image's next version. Open it in Shot and every layer is still live: the marks, the placed images, the padding, the style and the crop. Lengths and positions are in the input file's pixels, from its top left, as in the record. Every field is optional, but an edit needs at least one:

```json
{
  "crop": [0, 0, 1600, 1000],
  "pad": 60,
  "background": "white",
  "style": { "shadow": "soft", "border": "hairline", "corners": 16 },
  "marks": [{ "type": "arrow", "from": [410, 220], "to": [612, 388], "color": "red" }],
  "remove": ["5F3A…"],
  "place": [{ "path": "Shot 2026-10-10 at 14.05.40.png", "at": [1700, 0], "width": 800 }],
  "scale": "1x",
  "format": "png"
}
```

| Field | Does |
|---|---|
| `crop` | Keeps `[x, y, width, height]`, applied after everything else, so with `pad` it can keep some of the padding |
| `pad` | Canvas around the image: one number for every side, or `[top, right, bottom, left]`, up to 4096 |
| `background` | Fills the padding: a palette name, a hex such as `#F2F2F7`, or `none` for transparent, which only a PNG can keep |
| `style` | The screenshot's `shadow` (`soft`, `float`, `contact`, `glow` or `none`), `border` (`hairline`, `solid`, `outline` or `none`, or `{"type": "solid", "width": 6, "color": "white"}`) and `corners`, a radius. What's left out stays as it is. An outline needs see-through pixels, and a window captured with its shadow takes no style. |
| `marks` | Marks to draw on top, in the [record's format](#the-capture-record), except `image` |
| `remove` | Layer ids to delete, from the record or an earlier edit's `layers` |
| `place` | Other images to put on top, each `{"path": …}`, with `at`, its top-left corner, else to the right of the image, and `width`, which keeps its proportions, else its own size |
| `scale` | `1x` halves a Retina image to one pixel per point, as [**Scale Retina captures to 1×**](#settings) does. The result keeps its marks in the record but opens flat. |
| `format` | `png` or `jpeg`, else the input's own. A JPEG's padding is white unless `background` says otherwise. |

The changes are made in the editor's order: `remove`, then `marks`, `place`, `style`, `pad`, `background` and last `crop`. A mistake names its field, such as `style.border.width must be pixels above 0` or `marks[2] (arrow): needs from and to, each [x, y]`, and nothing is written. `shot annotate` is an edit with only `marks`, and `shot crop` one with only `crop`.

## Edit a video

For a video, `shot edit` and the MCP server's `edit_video` tool make the video editor's changes and export it, from one JSON object. It's how an agent turns a test recording into pull-request media: cut the dead time, speed it up, mute it, point at the moment the bug happens, and keep it under GitHub's size limit. The result is a new file beside the recording, and **Edit** on it opens the edit in the video editor, still live. Times are seconds of the input, such as `2.5`, or text such as `"1:02.5"`, as `get_frames` and `shot frames` give them. Positions are its pixels, from its top left. Every field is optional, but an edit needs at least one:

```json
{
  "keep": [[2, 9.5], [14, 20]],
  "speed": 2,
  "mute": true,
  "crop": [0, 0, 1600, 1000],
  "marks": [{ "start": 3, "end": 6, "type": "arrow", "from": [410, 220], "to": [612, 388], "color": "red" }],
  "append": ["Recording 2026-10-10 at 14.08.02.mp4"],
  "format": "gif",
  "maxBytes": 10000000,
  "fps": 12,
  "width": 720
}
```

| Field | Does |
|---|---|
| `keep` | The parts to keep, each `[start, end]`, in order. Everything around and between them is cut. |
| `cut` | The parts to cut instead, each `[start, end]` |
| `speed` | How fast it plays, from 0.25 to 4. A GIF can always change speed. An MP4 or MOV can only when it's just kept or cut, as with the editor's export. |
| `mute` | `true` leaves out the sound |
| `crop` | Keeps `[x, y, width, height]` of the picture. The edit opens with the canvas at that size and the recording moved and scaled within it, rather than with the video editor's adjustable frame crop. |
| `marks` | Marks in the [record's format](#the-capture-record), except `image`, each shown from `start` to `end`, or for 3 seconds without one. They're timed and placed in the input, and move with the cuts. |
| `append` | Other videos to play after it, in order |
| `format` | `mp4`, `mov` or `gif`. Without it, an MP4 or MOV keeps its own format, and anything else becomes an MP4. |
| `maxBytes` | The most the file may be, such as `10000000` for 10 MB. A GIF lowers its frame rate, then its width, until it fits. An MP4 or MOV that has to be drawn again, with marks, a crop or appended videos, is drawn at three quarters, then half, then smaller. |
| `fps` and `width` | A GIF's frames per second, 12 by default, and width at most, 720 by default, or 0 for the video's own |

A video that's an earlier edit is edited again from its project, so its marks and cuts stay live. A mistake names its field, such as `keep[1] starts before keep[0] ends` or `speed changes only a GIF, or a video that's only kept or cut`, and nothing is written. `shot trim` is an edit with only `keep`, and `shot gif` one that's a GIF.
