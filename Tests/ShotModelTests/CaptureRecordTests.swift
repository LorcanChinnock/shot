import Foundation
import Testing
@testable import ShotModel

private let record = CaptureRecord(
    original: "Shot 2026-10-10 at 14.03.12.png",
    kind: "image",
    created: Date(timeIntervalSince1970: 1_791_640_992),
    size: CaptureRecord.Size(width: 2880, height: 1800),
    scale: 2,
    source: CaptureRecord.Source(mode: "window", app: "Simulator", bundleID: "com.apple.iphonesimulator", windowTitle: "iPhone 17 Pro", screenFrame: CaptureRecord.Frame(x: 120, y: 80, width: 1440, height: 900)),
    canvas: [0, 0, 2880, 1800],
    annotations: [
        CaptureMark(id: "1", type: "arrow", from: [410, 220], to: [612, 388], color: "red", hex: "#FF3B30", lineWidth: 4),
        CaptureMark(id: "2", type: "blur", rect: [40, 40, 300, 30], note: "redacted, content hidden", amount: 0.008),
        CaptureMark(id: "3", type: "pen", rect: [10, 10, 20, 5], points: [[10, 10], [30, 15]], color: "red"),
        CaptureMark(id: "4", type: "note", rect: [600, 450, 180, 32], text: "too tight here", color: "yellow"),
    ]
)

@Test func theRecordRoundTrips() throws {
    #expect(try CaptureRecord.decoded(from: record.encoded()) == record)
    let now = CaptureRecord(kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992.437), size: record.size, scale: record.scale)
    #expect(try CaptureRecord.decoded(from: now.encoded()) == now)
}

@Test func theRecordWritesTheVersionedSchemaAndLeavesUnusedFieldsOut() throws {
    let text = try #require(String(data: record.encoded(), encoding: .utf8))
    #expect(text.contains(#""schema":"shot.capture/2""#))
    #expect(text.contains(#""coordinateSpace":"image pixels, top-left origin""#))
    #expect(text.contains(#""created":"2026-10-10T14:03:12Z""#))
    // The arrow has no rect and the blur no colour, so neither key appears for them.
    let json = try #require(try JSONSerialization.jsonObject(with: record.encoded()) as? [String: Any])
    let annotations = try #require(json["annotations"] as? [[String: Any]])
    #expect(Set(annotations[0].keys) == ["id", "type", "from", "to", "color", "hex", "lineWidth"])
    #expect(Set(annotations[1].keys) == ["id", "type", "rect", "note", "amount"])
}

@Test func aCaptureWithoutSourceOrOriginalLeavesThemOut() throws {
    let plain = CaptureRecord(kind: "image", created: Date(timeIntervalSince1970: 0), size: .init(width: 1, height: 1), scale: 1)
    let json = try #require(try JSONSerialization.jsonObject(with: plain.encoded()) as? [String: Any])
    #expect(json["source"] == nil)
    #expect(json["original"] == nil)
    #expect(json["canvas"] == nil)
    #expect(json["editable"] == nil)
    #expect((json["annotations"] as? [Any])?.isEmpty == true)
}

/// Shot 0.7.0-beta.39 wrote these as `.shot.json` files; they still read, with `file` ignored.
@Test func aFirstSchemaSidecarStillDecodes() throws {
    let old = #"""
    {"schema":"shot.capture/1","file":"Shot (2).png","original":"Shot.png","kind":"image","created":"2026-10-10T14:03:12Z",
     "size":{"width":10,"height":10},"scale":2,"coordinateSpace":"image pixels, top-left origin",
     "annotations":[{"id":"1","type":"counter","center":[5,5],"number":1,"color":"red","hex":"#FF3B30"}]}
    """#
    let decoded = try CaptureRecord.decoded(from: Data(old.utf8))
    #expect(decoded.schema == "shot.capture/1")
    #expect(decoded.original == "Shot.png")
    #expect(decoded.annotations == [CaptureMark(id: "1", type: "counter", center: [5, 5], number: 1, color: "red", hex: "#FF3B30")])
}

@Test func aMarkMayLeaveOutItsID() throws {
    let mark = try JSONDecoder().decode(CaptureMark.self, from: Data(#"{"type":"rectangle","rect":[1,2,3,4],"color":"red"}"#.utf8))
    #expect(mark == CaptureMark(type: "rectangle", rect: [1, 2, 3, 4], color: "red"))
}

@Test func theSummarySaysWhereItCameFromWhatWasNotedAndWhatIsRedacted() {
    #expect(record.summaryLines == [
        #"Captured from: Simulator, window "iPhone 17 Pro" (window capture)."#,
        "Saved in Shot's editor from Shot 2026-10-10 at 14.03.12.png, which is in the same folder.",
        #"The user's notes: "too tight here"."#,
        "1 area is redacted on purpose: don't try to read or guess what's under it.",
        "What the user marked, in the file's pixels (top-left origin):",
        "- arrow from (410, 220) to (612, 388), red",
        "- blur at (40, 40), 300×30 (redacted, content hidden)",
        "- pen at (10, 10), 20×5, red",
        #"- note "too tight here" at (600, 450), 180×32, yellow"#,
    ])
}

@Test func aBareRecordHasNothingToSay() {
    #expect(CaptureRecord(kind: "image", created: Date(), size: .init(width: 1, height: 1), scale: 1).summaryLines.isEmpty)
    let counter = CaptureRecord(kind: "image", created: Date(), size: .init(width: 1, height: 1), scale: 1, annotations: [CaptureMark(type: "counter", center: [2.5, 3], number: 2)])
    #expect(counter.summaryLines.last == "- counter 2 at (2.5, 3)")
}
