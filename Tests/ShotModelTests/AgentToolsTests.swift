import Foundation
import Testing
@testable import ShotModel

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let utc = TimeZone(identifier: "UTC")!

private func tools(in folder: URL, _ names: [(String, Double, Bool)], records: [String: CaptureRecord] = [:]) -> AgentTools {
    let entries = names.map { name, minutesAgo, video in
        AgentCaptures.Entry(url: folder.appendingPathComponent(name), isVideo: video, date: now.addingTimeInterval(-minutesAgo * 60))
    }
    return AgentTools(
        folder: folder,
        entries: { entries },
        preview: { entry in [.image(data: "PREVIEW:\(entry.name)", mimeType: "image/jpeg")] },
        record: { records[$0.name] },
        now: { now },
        timeZone: utc
    )
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AgentToolsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func texts(_ result: MCPServer.ToolResult) -> [String] {
    result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }
}

private let folder = URL(fileURLWithPath: "/shots")
private let captures = tools(in: folder, [
    ("Shot A.png", 30, false),
    ("Shot A (2).png", 20, false),
    ("Shot B.png", 10, false),
    ("Recording C.mp4", 5, true),
])

@Test func thereAreThreeToolsEachWithAnObjectSchema() {
    #expect(AgentTools.definitions.map(\.name) == ["latest_capture", "list_captures", "get_capture"])
    for tool in AgentTools.definitions {
        #expect(tool.inputSchema["type"] == .string("object"))
        #expect(!tool.description.isEmpty)
    }
}

@Test func latestCaptureDefaultsToTheNewestImage() async {
    let result = await captures.call("latest_capture", .object([:]))
    #expect(result.isError == false)
    #expect(result.content.first == .image(data: "PREVIEW:Shot B.png", mimeType: "image/jpeg"))
    #expect(texts(result).first?.contains(#""path" : "/shots/Shot B.png""#) == true)
}

@Test(arguments: [("video", "Recording C.mp4"), ("ANY", "Recording C.mp4"), ("pictures", "Recording C.mp4"), ("image", "Shot B.png")])
func latestCaptureReadsKindLeniently(_ kind: String, _ expected: String) async {
    let result = await captures.call("latest_capture", .object(["kind": .string(kind)]))
    #expect(result.content.first == .image(data: "PREVIEW:\(expected)", mimeType: "image/jpeg"))
}

@Test func theMetadataSaysWhatAndWhen() async {
    let result = await captures.call("latest_capture", .object(["kind": .string("video")]))
    let metadata = try? JSONDecoder().decode(JSONValue.self, from: Data((texts(result).first ?? "").utf8))
    #expect(metadata == .object([
        "name": .string("Recording C.mp4"),
        "path": .string("/shots/Recording C.mp4"),
        "kind": .string("video"),
        "created": .string("2027-01-15T07:55:00Z"),
    ]))
}

@Test func anImageWithoutARecordSaysHowToGetOne() async {
    let result = await captures.call("latest_capture", .object([:]))
    #expect(texts(result).last?.contains("Hand captures to agents") == true)
}

@Test func theRecordIsSummarisedInPlainLines() async throws {
    let record = CaptureRecord(
        original: "Shot A.png", kind: "image", created: now, size: .init(width: 100, height: 100), scale: 1,
        annotations: [CaptureMark(id: "1", type: "arrow", from: [1, 2], to: [3, 4], color: "red")]
    )
    let tools = tools(in: URL(fileURLWithPath: "/shots"), [("Shot A.png", 30, false), ("Shot A (2).png", 20, false)], records: ["Shot A (2).png": record])
    let result = await tools.call("latest_capture", .object([:]))
    #expect(result.content.first == .image(data: "PREVIEW:Shot A (2).png", mimeType: "image/jpeg"))
    #expect(texts(result).last == record.summaryLines.joined(separator: "\n"))
    #expect(texts(result).first?.contains("shotJSON") == false)
}

@Test func anEmptyFolderIsNotAnErrorAndSaysWhereItLooked() async {
    let tools = tools(in: URL(fileURLWithPath: "/Users/me/Desktop"), [])
    for name in ["latest_capture", "list_captures", "get_capture"] {
        let result = await tools.call(name, .object([:]))
        #expect(result.isError == false)
        #expect(texts(result).joined().contains("in /Users/me/Desktop yet"))
        #expect(result.content.count == 1)
    }
}

@Test func noLatestRecordingNamesTheKind() async {
    let tools = tools(in: folder, [("Shot B.png", 10, false)])
    let result = await tools.call("latest_capture", .object(["kind": .string("video")]))
    #expect(texts(result) == ["No recordings in /shots yet."])
}

@Test func listCapturesIsMetadataOnlyNewestFirst() async throws {
    let result = await captures.call("list_captures", .object([:]))
    #expect(result.content.count == 1)
    let list = try JSONDecoder().decode([[String: String]].self, from: Data(texts(result)[0].utf8))
    #expect(list.map { $0["name"] } == ["Recording C.mp4", "Shot B.png", "Shot A (2).png"])
}

@Test(arguments: [(JSONValue.number(2), 2), (.string("1"), 1), (.number(0), 1), (.number(-5), 1), (.number(1e300), 3), (.string("inf"), 3), (.string("lots"), 3)])
func listCapturesClampsTheLimit(_ limit: JSONValue, _ count: Int) async throws {
    let result = await captures.call("list_captures", .object(["limit": limit]))
    let list = try JSONDecoder().decode([JSONValue].self, from: Data(texts(result)[0].utf8))
    #expect(list.count == count)
}

@Test func listCapturesFiltersBySince() async throws {
    let result = await captures.call("list_captures", .object(["since": .string("15m")]))
    let list = try JSONDecoder().decode([[String: String]].self, from: Data(texts(result)[0].utf8))
    #expect(list.map { $0["name"] } == ["Recording C.mp4", "Shot B.png"])
    let none = await captures.call("list_captures", .object(["since": .string("1m")]))
    #expect(texts(none) == ["No captures in /shots since 2027-01-15T07:59:00Z."])
}

@Test func anUnreadableSinceListsEverythingAndSaysSo() async throws {
    let result = await captures.call("list_captures", .object(["since": .string("last tuesday")]))
    #expect(result.isError == false)
    let lines = texts(result)[0].split(separator: "\n", maxSplits: 1).map(String.init)
    #expect(lines[0] == #"Couldn't read since "last tuesday", so these are from any time."#)
    #expect(try JSONDecoder().decode([JSONValue].self, from: Data(lines[1].utf8)).count == 3)
}

@Test func getCaptureFindsByLooseNameOrPath() async {
    let byName = await captures.call("get_capture", .object(["name": .string("shot a")]))
    #expect(byName.content.first == .image(data: "PREVIEW:Shot A (2).png", mimeType: "image/jpeg"))
    let byPath = await captures.call("get_capture", .object(["path": .string("/shots/Shot A.png")]))
    #expect(byPath.content.first == .image(data: "PREVIEW:Shot A.png", mimeType: "image/jpeg"))
    let blankPath = await captures.call("get_capture", .object(["path": .string(" "), "name": .string("recording")]))
    #expect(blankPath.content.first == .image(data: "PREVIEW:Recording C.mp4", mimeType: "image/jpeg"))
}

@Test func getCaptureWithNothingToFindGivesTheNewest() async {
    let result = await captures.call("get_capture", .object([:]))
    #expect(result.content.first == .image(data: "PREVIEW:Recording C.mp4", mimeType: "image/jpeg"))
}

@Test func getCaptureNotFoundIsAnErrorNamingTheNearest() async {
    let result = await captures.call("get_capture", .object(["name": .string("shot zebra")]))
    #expect(result.isError)
    #expect(texts(result) == [#"No capture matches "shot zebra". The nearest are "Shot B.png", "Shot A (2).png", "Recording C.mp4"."#])
    let nothingShared = await captures.call("get_capture", .object(["name": .string("zebra")]))
    #expect(texts(nothingShared) == [#"No capture matches "zebra". The newest are "Recording C.mp4", "Shot B.png", "Shot A (2).png"."#])
}

@Test func theServerRunsTheToolsOverJSONRPC() async {
    let server = captures.server(version: "1.2.3")
    let list = await server.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    #expect(list?.contains(#""name":"get_capture""#) == true)
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"Latest-Capture","arguments":{"kind":"video"}}}"#)
    #expect(reply?.contains(#""data":"PREVIEW:Recording C.mp4""#) == true)
    #expect(reply?.contains(#""isError":false"#) == true)
}
