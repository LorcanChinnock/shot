import Foundation
import Testing
@testable import ShotCore

private func parse(_ json: String) throws(ShotCommandError) -> ImageEdit {
    try ImageEdit.parse(Data(json.utf8))
}

/// The message of the error `json` gives, or nil if it parses.
private func problem(_ json: String) -> String? {
    do {
        _ = try parse(json)
        return nil
    } catch {
        guard case let .data(message) = error else { return "not a data error: \(error)" }
        return message
    }
}

@Test func everyFieldOfAnEditParses() throws {
    let edit = try parse("""
    {
      "crop": [10, 20.5, 300, 40],
      "pad": [1, 2, 3, 4],
      "background": "#F2F2F7",
      "style": {"shadow": "Soft", "border": {"type": "solid", "width": 6, "color": "white"}, "corners": 12},
      "marks": [{"type": "arrow", "from": [1, 2], "to": [3, 4], "color": "red"}],
      "remove": ["5F3A0000-0000-0000-0000-000000000000"],
      "place": [{"path": "other.png", "at": [40, 50], "width": 300}],
      "scale": "1x",
      "format": "jpg"
    }
    """)
    #expect(edit == ImageEdit(
        crop: [10, 20.5, 300, 40], pad: [1, 2, 3, 4], background: "#F2F2F7",
        style: ImageEdit.Style(shadow: "soft", border: ImageEdit.Border(type: "solid", width: 6, color: "white"), corners: 12),
        marks: [CaptureMark(type: "arrow", from: [1, 2], to: [3, 4], color: "red")], remove: ["5F3A0000-0000-0000-0000-000000000000"],
        place: [ImageEdit.Placement(path: "other.png", at: [40, 50], width: 300)], scale: "1x", format: .jpeg
    ))
    #expect(edit.isOneX)
}

@Test func shortFormsReadAsTheLongOnes() throws {
    #expect(try parse(#"{"pad": 40}"#).pad == [40, 40, 40, 40])
    #expect(try parse(#"{"style": {"border": "hairline"}}"#).style == ImageEdit.Style(border: ImageEdit.Border(type: "hairline")))
    #expect(try parse(#"{"style": {"shadow": "none", "border": "none", "corners": 0}}"#).style == ImageEdit.Style(shadow: "none", border: ImageEdit.Border(type: "none"), corners: 0))
    #expect(try parse(#"{"background": "none"}"#).background == "none")
    #expect(try parse(#"{"scale": "1×", "format": "PNG"}"#) == ImageEdit(scale: "1x", format: .png))
    // A null leaves a field as it is, as if it weren't there.
    #expect(try parse(#"{"crop": null, "pad": 8}"#) == ImageEdit(pad: [8, 8, 8, 8]))
}

@Test(arguments: [
    ("[]", "the edit must be a JSON object with any of crop, pad, background, style, marks, remove, place, scale or format"),
    ("{}", "the edit changes nothing; give at least one of crop, pad, background, style, marks, remove, place, scale or format"),
    (#"{"cropp": [0, 0, 1, 1]}"#, #"unknown field "cropp"; an edit takes crop, pad, background, style, marks, remove, place, scale or format"#),
    (#"{"crop": [0, 0, 0, 10]}"#, "crop must be [x, y, width, height] in the image's pixels, with a width and height above 0"),
    (#"{"crop": ["0", 0, 10, 10]}"#, "crop must be [x, y, width, height] in the image's pixels, with a width and height above 0"),
    (#"{"pad": -1}"#, "pad must be pixels from 0 to 4096, one number for every side or [top, right, bottom, left]"),
    (#"{"pad": [1, 2]}"#, "pad must be pixels from 0 to 4096, one number for every side or [top, right, bottom, left]"),
    (#"{"pad": 5000}"#, "pad must be pixels from 0 to 4096, one number for every side or [top, right, bottom, left]"),
    (#"{"background": "teal"}"#, "background must be a palette name (red, orange, yellow, green, blue, black or white) or a colour such as #FF3B30, or none for transparent"),
    (#"{"style": "soft"}"#, "style must be an object with any of shadow, border or corners"),
    (#"{"style": {}}"#, "style needs at least one of shadow, border or corners"),
    (#"{"style": {"glow": true}}"#, #"unknown field "style.glow"; style takes shadow, border or corners"#),
    (#"{"style": {"shadow": "huge"}}"#, "style.shadow must be soft, float, contact, glow or none"),
    (#"{"style": {"corners": -2}}"#, "style.corners must be a radius in pixels, 0 or more"),
    (#"{"style": {"border": "dashed"}}"#, #"style.border must be hairline, solid, outline or none, or an object such as {"type": "solid", "width": 4, "color": "white"}"#),
    (#"{"style": {"border": {"width": 4}}}"#, "style.border.type must be hairline, solid, outline or none"),
    (#"{"style": {"border": {"type": "solid", "width": 0}}}"#, "style.border.width must be pixels above 0"),
    (#"{"style": {"border": {"type": "hairline", "width": 2}}}"#, "style.border.width is only for a solid border or an outline; a hairline has none"),
    (#"{"style": {"border": {"type": "solid", "color": "mauve"}}}"#, "style.border.color must be a palette name (red, orange, yellow, green, blue, black or white) or a colour such as #FF3B30"),
    (#"{"style": {"border": {"type": "solid", "dash": 2}}}"#, #"unknown field "style.border.dash"; a border takes type, width or color"#),
    (#"{"marks": {"type": "arrow"}}"#, "marks must be an array of marks, in the capture record's format"),
    (#"{"marks": [{"type": "rectangle", "rect": [0, 0, 1, 1]}, {"type": "arrow", "from": [1, 1]}]}"#, "marks[1] (arrow): needs from and to, each [x, y]"),
    (#"{"marks": [{"type": "image", "rect": [0, 0, 1, 1]}]}"#, "marks[0] (image): a placed image can't be drawn from a record, which doesn't hold its pixels; use place"),
    (#"{"marks": [3]}"#, "marks[0] isn't a mark: it needs a type, and its fields must be the record's"),
    (#"{"remove": "abc"}"#, "remove must be an array of layer ids, as the capture record lists them"),
    (#"{"remove": ["a", " "]}"#, "remove[1] must be a layer's id, as the capture record lists it"),
    (#"{"place": [{"at": [0, 0]}]}"#, "place[0].path must name the image to place"),
    (#"{"place": [{"path": "a.png", "at": [0]}]}"#, "place[0].at must be [x, y], its top-left corner in the image's pixels"),
    (#"{"place": [{"path": "a.png", "width": 0}]}"#, "place[0].width must be pixels from 1 to 16384"),
    (#"{"place": [{"path": "a.png", "scale": 2}]}"#, #"unknown field "place[0].scale"; an image to place takes path, at or width"#),
    (#"{"scale": 0.5}"#, #"scale must be "1x", which scales a Retina image to one pixel per point"#),
    (#"{"format": "heic"}"#, "format must be png or jpeg"),
])
func aBadEditNamesTheFieldThatsWrong(_ json: String, _ message: String) {
    #expect(problem(json) == message)
}

@Test func notJSONAtAllIsADataError() {
    #expect(problem("crop 0 0 10 10")?.hasPrefix("the edit isn't JSON") == true)
}

@Test func theToolsOwnArgumentsCanBeIgnored() throws {
    let arguments: JSONValue = .object(["path": .string("a.png"), "pad": .number(4)])
    #expect(try ImageEdit.parse(arguments, ignoring: ["path", "name"]) == ImageEdit(pad: [4, 4, 4, 4]))
    #expect(throws: ShotCommandError.self) { try ImageEdit.parse(arguments) }
}
