# Annotation editor

![The editor toolbar: the tools, then the colours and line widths for the arrow tool](../../../docs/media/editor-toolbar.png)

Open the editor from a Quick Access card, with **Annotate** in the [gallery](#gallery), by turning on **Open in editor** in Settings › Capture, or with [`shot://annotate`](#url-scheme).

## Tools

Press a tool's key when you aren't typing text.

| Key | Tool |
|---|---|
| V | Select: move, resize and restyle what you've drawn |
| H | Hand: drag to move around when zoomed in, without touching annotations |
| A | Arrow |
| L | Line |
| R | Shape: rectangle, ellipse, triangle, diamond or star |
| D | Pen: freehand |
| T | Text |
| S | Sticky note |
| M | Highlight: a freehand marker |
| F | Spotlight: dims or blurs everything outside the area |
| B | Redact: blurs or pixelates the area |
| N | Counter: numbered circles |
| C | Crop: keep part of the image, or of the placed image selected |

Hover a tool to see what it does. While you draw, Shift keeps a box square, keeps an arrow, line or highlight at 45° steps, and Option draws from the centre. Esc cancels what you're drawing.

Tools that draw a mark show their options below the tools:

- **Colour and width:** a colour and one of three line widths. For text, sticky notes and counters the widths are text sizes, and changing the size or colour while you type updates the text as you go.
- **Text and sticky notes:** left, centre or right alignment for their lines.
- **Shape:** the shape and a fill.
- **Redact:** blur or pixelate, and an amount slider for how far the blur spreads or how big the blocks are.
- **Crop:** the aspect to hold the crop to (Free, 1:1, 4:3 or 16:9), and **Reset** to take the crop off. They show only while the crop tool is active.
- **Spotlight:** its shape (rectangle or ellipse), a soft edge that fades it into the dim, whether to darken or blur outside it, and how strongly. The effect and strength apply to every spotlight in the image, since they share one dim.

The highlight and sticky notes keep their own colours, yellow at first, so they don't take the colour of your arrows. The last swatch picks any colour, and each palette remembers the last one you picked. Its eyedropper samples a colour from anywhere on screen, such as a brand colour in the screenshot itself. Esc cancels it. The video editor's palettes work the same way.

The editor remembers the options you last used and the last drawing tool. A new window starts with that tool, or with the arrow.

## Cropping

Press C, or click the **Frame** row in Layers, to crop. The view shows everything, including what's cropped off, dimmed and greyed out, and the crop has eight handles:

- Drag a handle to resize the crop, in or out. An edge can go as far as the content reaches: the image, any padding and your annotations, so dragging outward brings cropped pixels back. Edges snap to the image's edges.
- Drag inside the crop to move it, or outside it to draw a new one.
- Hold Shift to keep the crop's current shape.
- **Aspect** holds the crop to Free, 1:1, 4:3 or 16:9. Picking a ratio fits the largest crop of that ratio inside the current one, centred, and the handles keep it as you drag. It follows the crop's orientation, wide or tall. The editor remembers the last one you picked.
- Return, picking another tool, ⌘C, ⌘S or clicking outside the canvas applies the crop as one undo step. Esc cancels. **Reset**, or Delete, makes the crop the whole image again.

With a placed image selected, C crops that image instead of the whole picture: see [Combine images](#combine-images).

Once the crop is applied, what's outside it is hidden but kept, annotations included, so press C again to adjust it. A shadow, border or rounded corners on the screenshot go around the cropped picture, so crop first and add the style afterwards.

## Editing annotations

- Click an annotation with the select tool to select it, then drag it, or drag its handles to resize it. Text and counters have no handles, and a placed image has handles at its corners only. Drag the middle handle of a line or arrow to bend it. Drag one of the round handles inside a shape's corners to round them all by the same amount, up to a pill on a rectangle; a triangle or diamond rounds each corner, and a star only its points. An ellipse has no corners, and the handles hide on a box too small to grab them. New shapes start square. Choosing a colour, width or option restyles the selection.
- While you drag a handle, Shift keeps a box in the proportions it had, or snaps an arrow or line end to 45° steps, and Option resizes from the centre, so the opposite side mirrors your drag. On a placed image, which keeps its proportions as you resize, Shift lets you stretch it freely. Hold Space to move the whole shape instead, and let go to carry on resizing. Pressing or releasing Shift or Option mid-drag updates the shape straight away. Sticky notes keep their own text-fitting rules and ignore both.
- What you've just drawn stays selected until you draw the next thing, click elsewhere or press Esc, so you can fix its shape, colour, width or fill from the toolbar, or drag its handles, without switching to the select tool. The change also applies to what you draw next.
- With the select tool, double-click text or a sticky note to edit it. Clicking a note with the note tool edits it too.
- Press Delete to remove the selection, and Esc to deselect. While you type in a text box or sticky note, Esc finishes it; ⌘Z removes it again.
- Arrow keys nudge the selected annotation by 1 pixel, or 10 with Shift.
- ⌘C copies the selected annotation, ⌘V pastes it, and ⌘D duplicates it. You can paste into another editor window. With nothing or several things selected, ⌘C copies the whole image.
- ⌘Z undoes and ⇧⌘Z redoes. What you had selected stays selected, so the toolbar shows its style as it is after the undo.
- With VoiceOver, the canvas lists its visible annotations, frontmost first, by their [layer names](#layers), with the full words of a text or note. Press one (VO-Space) to select it.

## Layers

Click **Layers** (⌘L) to list the annotations, frontmost first, with the image locked at the bottom. A cropped image also has a **Frame** row pinned at the top: click it to adjust the crop, use its eye to show the uncropped image and leave the crop out of Copy and Save, and press Delete or click its bin to remove the crop. It can't be moved, locked or duplicated. Click a row to select it on the canvas, ⌘-click or ⇧-click to select several, drag a row by its handle to reorder (Escape or dropping outside the list cancels), and press Delete or click the bin to delete. The eye hides a layer, which also leaves it out of Copy and Save, and the lock stops it being picked on the canvas, moved or deleted. You can still select a locked layer in the list and drag it to another place. Right-click a row to rename, duplicate, delete, lock or hide, and a placed image's row to crop it. A placed image with its own crop shows a crop badge: click it to adjust the crop, or right-click the row and choose **Reset Crop** to show the whole image again.

A layer is named after its kind, or the first words of a text or note. To give it your own name, double-click the name, or select the row and press Return. Return or clicking elsewhere keeps the new name, and Esc cancels. Clear the name to go back to the automatic one. The name shows only in the list, never in the image. Renaming is one undo step, and a duplicate keeps the name. ⌘] and ⌘[ move the selection forward and back, and ⌥⌘] and ⌥⌘[ bring it to the front or send it to the back.

Each layer acts on everything under it and nothing over it: a blur, pixelate or spotlight covers the layers below it, and layers above it are drawn over it. All spotlights share one dim, at the lowest spotlight's place in the list.

## Canvas

Annotations can reach past the edges of the screenshot: the canvas grows to fit them, except for spotlights. That holds for a cropped image too: the padding grows behind the crop and shows again when you uncrop. In the **Canvas** menu, **Fit to Content** fits the canvas to everything on it, and **Trim to Image** trims it back to the screenshot. Its **Background…** item sets the colour of the extra space with the same swatches as the toolbar: transparent (PNG only), a palette colour, or any colour from the rainbow swatch, which remembers the last one you picked. It starts transparent for a PNG and white for a JPEG.

## Style

Click **Style** in the toolbar to round the corners of your screenshot and give it a shadow or a border. With something selected, Style acts on that instead. Nothing is styled until you ask, and each preset shows your screenshot, image, mark or text with that preset on it.

| Selected | Style offers |
|---|---|
| Nothing: the screenshot | Shadow, border and corners |
| A placed image | The same as the screenshot |
| A shape, arrow, line, pen stroke or counter | A shadow or glow |
| Text | A shadow or glow, and an outline |
| A blur, pixelate, spotlight, highlight or note | Nothing, so Style is greyed out. A note has a shadow of its own. |
| Several things, or a locked one | Nothing |

Style is also greyed out while you type text.

- **Shadow:** None, Soft, Float, Contact or Glow. Point at one to preview it on the canvas, and click to apply it. The arrow keys move between the presets, previewing each, and Return applies the one they're on. Once there's a shadow, **Elevation** and **Opacity** sliders tune it into a custom one. The light comes from above, so shadows fall below. On a coloured background the shadow takes a dark shade of it. On a transparent one it's black, and it's saved in the PNG so it looks right pasted anywhere. Glow takes the colour of the image's edge, or of the shape, arrow or text.
- **macOS window shadow:** a window captured with the macOS shadow already has one, so Style shows **Uses macOS window shadow** in place of its choices. Its image includes the shadow's see-through margin, which a second shadow, a border or corners would go round. Pasted styles and Use this style for new captures leave it as it is.
- **Border:** **Hairline** draws a one-pixel rim, light on dark content and dark on light, so a screenshot keeps its edge on a page of the same colour. **Solid** draws a line of one colour just outside the edge, following the rounded corners. **Outline** shows only for a screenshot or image with see-through pixels, such as a logo or a cut-out: it traces the image's shape, like a sticker. On text, Outline strokes round each letter, so it reads on a busy screenshot. Solid and Outline offer three widths, **S**, **M** and **L**, and the palette colours. They start at M, in the colour of the border already there, or else white, or on text black or white to stand out from its colour.
- **Corners:** the slider rounds the corners of the screenshot or an image.

A shadow or border on the screenshot grows the canvas just enough to fit it, and removing it shrinks the canvas back. Each click is one undo step, and so is each slider drag.

A style you pick in Style for an image, a mark or text is remembered: the next one of that kind you draw or add starts with it, even in a new editor window, until you pick None. Paste Style and Apply Style to All Images don't change what's remembered.

The screenshot starts plain unless you turn on **Use this style for new captures**, at the bottom of Style when nothing is selected. Turning it on saves the screenshot's current style, and each new capture gets that style when you open it in the editor. New captures are also copied with that style: the plain capture is copied straight away, and the styled one replaces it a moment later, unless you've copied something else since. Quick Access also switches to the styled capture after a moment, and copying or dragging the card uses it. The saved file stays plain, so you can still change the style. To stop, turn the switch off. To save a new style, style a screenshot differently and turn the switch on again. The switch is on only while this screenshot has the saved style. If you restyle the screenshot, the switch turns off, but new captures keep the saved style, and a line under the switch says so. To stop styling new captures from there, turn the switch on and then off.

To reuse a style, select something and choose **Edit › Copy Style** (⌥⌘C), then select something else and choose **Paste Style** (⌥⌘V); with nothing selected, they copy from and paste on the screenshot. A style copied here pastes in the video editor too, and the other way round. Each thing takes only what it can have: a shape keeps its own corners, and text takes only an outline as its border. Copy Style needs one thing selected; Paste Style pastes on everything selected. **Edit › Apply Style to All Images** pastes it on the screenshot and every image you placed. Pasting is one undo step.

## Combine images

Click **Add an image** (⇧⌘I) to pick one of your recent captures, or **Choose File…** for any image files. You can also drag an image file or a Quick Access card onto the canvas, or press ⌘V with an image on the clipboard, to place another image beside your screenshot. A picked image goes beside the canvas. A dropped image is centred where you drop it; a pasted one goes beside the canvas. Placed images keep their full resolution, keep their aspect ratio when you resize them, and can be moved, nudged, copied and deleted like any other annotation.

To trim a placed image's own edges, such as a pasted screenshot's toolbar, double-click it, select it and press C, or right-click it and choose **Crop Image**. Cropping works as it does for the [whole picture](#cropping): the handles go on the image, the part cropped off shows dimmed, and **Aspect** and **Reset** work the same. Return applies the crop as one undo step and Esc cancels. Double-click it again to drag the edges back out. Its shadow, border and rounded corners go around the cropped edge, and resizing it scales what's left. Copies, duplicates and pastes keep the crop, and Paste Style leaves it alone. The crop of the whole picture still applies on top, so it can cut off part of a placed image too.

## Zoom

Pinch, or press ⌘+ and ⌘-, to zoom. ⌘0 fits the canvas to the window and ⌘1 shows it at actual size. When zoomed in, scroll, hold Space and drag, drag with the middle mouse button, or drag with the hand tool (H) to move around.

## Saving

**Copy** copies the annotated image. **Save** (⌘S) writes it beside the original as `name (2).png` (or `.jpg`), then `name (3).png` and so on, and copies it; the original is never changed. Unsaved changes show **EDITED** in the title bar, and closing the window asks whether to save them. Opening a version you saved this way, from the gallery, Quick Access or a `shot://annotate` link, opens the file it came from with every layer still live, so you can move, change or delete them; Save then writes the next version. This follows the file it came from when you move or rename it. If that file is gone or another image has replaced it, the version opens flattened. To edit the version as a plain image instead, choose **Edit › Flatten**, or open the file it came from. Shot keeps the layers in its own Application Support folder, not in the image, so a version you share never carries hidden layers or the full-size images you placed. A version saved by an older Shot reopens live only if [**Hand captures to agents**](#using-shot-with-ai-agents) was on when you saved it, and only if it has no placed images, spotlights, styled marks, aligned text, hidden layers or styled screenshot.

![A saved version reopened in the editor as the screenshot it came from, with its counter, box and arrow still live: the arrow is selected with its handles, and the Layers panel lists Step 1, Rectangle and Arrow](../../../docs/media/editor-versions.png)

An agent's `annotate`, `redact` or `crop`, from the [`shot` command](#the-shot-command-line) or the [MCP server](#the-mcp-server), saves the same way. On a version, it draws on the file it came from with the version's layers, so your marks stay live and the agent's go on top. It differs from Save in three ways:

- It never copies, shows a Quick Access card or opens the editor.
- With `-o`, it writes the name you give.
- The `shot` command also takes an image outside your save folder, and writes the version beside that image. That version isn't in the gallery, but it still reopens live.
