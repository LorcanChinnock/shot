import Foundation
import Testing
@testable import ShotModel

private let sidecar = CaptureSidecar(
    file: "Shot 2026-10-10 at 14.03.12 (2).png",
    original: "Shot 2026-10-10 at 14.03.12.png",
    kind: "image",
    created: Date(timeIntervalSince1970: 1_791_640_992),
    size: CaptureSidecar.Size(width: 2880, height: 1800),
    scale: 2,
    source: CaptureSidecar.Source(mode: "window", app: "Simulator", bundleID: "com.apple.iphonesimulator", windowTitle: "iPhone 17 Pro", screenFrame: CaptureSidecar.Frame(x: 120, y: 80, width: 1440, height: 900)),
    annotations: [
        SidecarAnnotation(id: "1", type: "arrow", from: [410, 220], to: [612, 388], color: "red", hex: "#FF3B30"),
        SidecarAnnotation(id: "2", type: "blur", rect: [40, 40, 300, 30], note: "redacted, content hidden"),
    ]
)

@Test func theSidecarSitsNextToItsCaptureWithTheWholeNameKept() {
    let url = CaptureSidecar.url(for: URL(fileURLWithPath: "/shots/Shot (2).png"))
    #expect(url.path == "/shots/Shot (2).png.shot.json")
}

@Test func theSidecarRoundTrips() throws {
    #expect(try CaptureSidecar.decoded(from: sidecar.encoded()) == sidecar)
    var now = sidecar
    now = CaptureSidecar(file: now.file, kind: now.kind, created: Date(timeIntervalSince1970: 1_791_640_992.437), size: now.size, scale: now.scale)
    #expect(try CaptureSidecar.decoded(from: now.encoded()) == now)
}

@Test func theSidecarWritesTheVersionedSchemaAndLeavesUnusedFieldsOut() throws {
    let text = try #require(String(data: sidecar.encoded(), encoding: .utf8))
    #expect(text.contains(#""schema" : "shot.capture/1""#))
    #expect(text.contains(#""coordinateSpace" : "image pixels, top-left origin""#))
    #expect(text.contains(#""created" : "2026-10-10T14:03:12Z""#))
    // The arrow has no rect and the blur no colour, so neither key appears for them.
    let json = try #require(try JSONSerialization.jsonObject(with: sidecar.encoded()) as? [String: Any])
    let annotations = try #require(json["annotations"] as? [[String: Any]])
    #expect(Set(annotations[0].keys) == ["id", "type", "from", "to", "color", "hex"])
    #expect(Set(annotations[1].keys) == ["id", "type", "rect", "note"])
}

@Test func aCaptureWithoutSourceOrOriginalLeavesThemOut() throws {
    let plain = CaptureSidecar(file: "a.png", kind: "image", created: Date(timeIntervalSince1970: 0), size: .init(width: 1, height: 1), scale: 1)
    let json = try #require(try JSONSerialization.jsonObject(with: plain.encoded()) as? [String: Any])
    #expect(json["source"] == nil)
    #expect(json["original"] == nil)
    #expect((json["annotations"] as? [Any])?.isEmpty == true)
}
