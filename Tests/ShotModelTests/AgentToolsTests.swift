import Foundation
import Synchronization
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

@Test func thereAreEighteenToolsEachWithAnObjectSchema() {
    #expect(AgentTools.definitions.map(\.name) == ["latest_capture", "list_captures", "get_capture", "get_frames", "find_text", "zoom", "wait_for_capture", "ask_for_capture", "annotate", "redact", "edit_image", "edit_video", "make_gif", "trim_video", "list_windows", "capture_window", "record_window", "compare"])
    let required = AgentTools.definitions.map { $0.inputSchema["required"] }
    #expect(required == [nil, nil, nil, nil, nil, .array([.string("rect")]), nil, nil, .array([.string("annotations")]), nil, nil, nil, nil, .array([.string("start"), .string("end")]), nil, nil, nil, .array([.string("a"), .string("b")])])
    for tool in AgentTools.definitions {
        #expect(tool.inputSchema["type"] == .string("object"))
        #expect(!tool.description.isEmpty)
    }
}

@Test func onlyTheToolsThatChangeNothingAreMarkedReadOnly() {
    // annotate, redact, edit_image, edit_video, make_gif, trim_video and compare add files, and capture_window and record_window take new captures.
    #expect(AgentTools.definitions.filter(\.readOnly).map(\.name) == ["latest_capture", "list_captures", "get_capture", "get_frames", "find_text", "zoom", "wait_for_capture", "list_windows"])
}

@Test func annotateNamesExactlyThePaletteColours() throws {
    let tool = try #require(AgentTools.definitions.first { $0.name == "annotate" })
    guard case let .string(description) = tool.inputSchema["properties"]?["annotations"]?["description"] else {
        Issue.record("annotate has no annotations description")
        return
    }
    let list = try #require(description.firstRange(of: "color (").flatMap { start in
        description[start.upperBound...].firstIndex(of: ")").map { description[start.upperBound..<$0] }
    })
    let named = list.replacingOccurrences(of: " or ", with: ", ").components(separatedBy: ", ")
    #expect(named == CaptureMark.paletteNames)
    #expect(Set(named) == CaptureMark.colorNames)
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

/// Captures with sizes and dates, as the live listing gives them, and an index that has read `texts` from them.
private func searchable(_ texts: [String: String], unread: [String] = []) -> AgentTools {
    let names = [("Shot A.png", 30.0), ("Invoice draft.png", 25), ("Shot B.png", 20), ("Recording C.mp4", 10), ("Shot D.png", 5)] + unread.map { ($0, 1.0) }
    let entries = names.map { name, minutesAgo in
        AgentCaptures.Entry(
            url: folder.appendingPathComponent(name), isVideo: name.hasSuffix(".mp4"), date: now.addingTimeInterval(-minutesAgo * 60),
            bytes: 100, modified: now.addingTimeInterval(-minutesAgo * 60)
        )
    }
    var index = TextIndex()
    for entry in entries {
        if let text = texts[entry.name], let bytes = entry.bytes, let modified = entry.modified {
            index.set(text, for: TextIndex.File(path: entry.url.path, bytes: bytes, modified: modified))
        }
    }
    let read = index
    return AgentTools(folder: folder, entries: { entries }, preview: { _ in [] }, textIndex: { read }, now: { now }, timeZone: utc)
}

private let readTexts = ["Invoice draft.png": "", "Shot A.png": "Settings\nINVOICE #42 paid", "Shot B.png": "Saved changes", "Shot D.png": "Café invoices\nTotal\ninvoice 1\ninvoice 2\ninvoice 3"]

@Test func listCapturesFindsCapturesByTheirTextOrName() async throws {
    let result = await searchable(readTexts).call("list_captures", .object(["query": .string(" invoice ")]))
    let list = try JSONDecoder().decode([JSONValue].self, from: Data(texts(result)[0].utf8))
    #expect(list.map { $0["name"]?.string } == ["Shot D.png", "Invoice draft.png", "Shot A.png"])
    #expect(list[0]["matchingLines"] == .array(["Café invoices", "invoice 1", "invoice 2"].map(JSONValue.string)))
    #expect(list[1]["matchingLines"] == nil)
    #expect(list[2]["matchingLines"] == .array([.string("INVOICE #42 paid")]))
}

@Test func listCapturesSearchesAccentsAndLimitsWhatItFound() async throws {
    let tools = searchable(readTexts)
    let cafe = try JSONDecoder().decode([JSONValue].self, from: Data(texts(await tools.call("list_captures", .object(["query": .string("CAFE")])))[0].utf8))
    #expect(cafe.map { $0["name"]?.string } == ["Shot D.png"])
    let one = try JSONDecoder().decode([JSONValue].self, from: Data(texts(await tools.call("list_captures", .object(["query": .string("invoice"), "limit": .number(1)])))[0].utf8))
    #expect(one.map { $0["name"]?.string } == ["Shot D.png"])
    let blank = try JSONDecoder().decode([JSONValue].self, from: Data(texts(await tools.call("list_captures", .object(["query": .string("  ")])))[0].utf8))
    #expect(blank.count == 5)
}

@Test func listCapturesSaysWhenNothingMatchesAndWhatIsntReadYet() async {
    let none = await searchable(readTexts).call("list_captures", .object(["query": .string("receipt")]))
    #expect(none.isError == false)
    #expect(texts(none) == [#"No captures in /shots have "receipt" in their name or text."#])
    let unread = await searchable(readTexts, unread: ["Shot E.png", "Shot F.gif"]).call("list_captures", .object(["query": .string("receipt")]))
    #expect(texts(unread).first?.hasPrefix("1 screenshot hasn't been read for search yet, so only its name is searched.") == true)
}

@Test func aStaleEntryIsntSearched() async throws {
    let tools = searchable(readTexts)
    let entries = tools.entries().map { entry in
        var changed = entry
        changed.bytes = 200
        return changed
    }
    var changed = tools
    changed.entries = { entries }
    let result = await changed.call("list_captures", .object(["query": .string("saved")]))
    #expect(texts(result).first?.contains("4 screenshots haven't been read") == true)
    #expect(texts(result).first?.hasSuffix(#"No captures in /shots have "saved" in their name or text."#) == true)
}

@Test func shotListSearchesAsTheToolDoes() throws {
    let tools = searchable(readTexts, unread: ["Shot E.png"])
    let notes = Mutex<[String]>([])
    let list = try tools.listJSON(limit: nil, since: nil, query: "saved") { note in notes.withLock { $0.append(note) } }
    guard case let .array(found) = list else {
        Issue.record("shot list gave \(list), not an array")
        return
    }
    #expect(found.map { $0["name"] } == [.string("Shot B.png")])
    #expect(found.first?["matchingLines"] == .array([.string("Saved changes")]))
    #expect(notes.withLock { $0.count } == 1)
    _ = try tools.listJSON(limit: nil, since: nil) { note in notes.withLock { $0.append(note) } }
    #expect(notes.withLock { $0.count } == 1)
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

@Test func aPathOutsideTheCaptureFolderSaysWhyItMatchesNothing() async {
    let outside = await captures.call("get_capture", .object(["path": .string("/shotsmore/Shot Z.png")]))
    #expect(texts(outside) == [#"No capture matches "/shotsmore/Shot Z.png". Only captures in Shot's capture folder, /shots, can be named, and that path is outside it. The nearest are "Shot B.png", "Shot A (2).png", "Recording C.mp4"."#])
    let inside = await captures.call("get_capture", .object(["path": .string("/shots/Shot Z.png")]))
    #expect(texts(inside).first?.contains("outside") == false)
}

@Test func theCommandLineGetsWhatTheToolsGiveAsJSON() throws {
    #expect(try captures.latestJSON(kind: .image)["name"] == .string("Shot B.png"))
    #expect(try captures.latestJSON(kind: .video)["path"] == .string("/shots/Recording C.mp4"))
    #expect(try captures.getJSON(nil)["name"] == .string("Recording C.mp4"))
    #expect(try captures.getJSON("shot b") == .object([
        "name": .string("Shot B.png"), "path": .string("/shots/Shot B.png"), "kind": .string("image"),
        "created": .string("2027-01-15T07:50:00Z"), "summary": .array([]),
    ]))
    #expect(try captures.listJSON(limit: 2, since: nil) == .array([captures.metadata(captures.entries()[3]), captures.metadata(captures.entries()[2])]))
    #expect(try captures.listJSON(limit: nil, since: "7m") == .array([captures.metadata(captures.entries()[3])]))
    #expect(try captures.listJSON(limit: nil, since: "1m") == .array([]))
}

@Test func theCommandLineSummarisesTheRecord() throws {
    let record = CaptureRecord(
        original: "Shot A.png", kind: "image", created: now, size: .init(width: 100, height: 100), scale: 1,
        annotations: [CaptureMark(id: "1", type: "arrow", from: [1, 2], to: [3, 4], color: "red")]
    )
    let tools = tools(in: folder, [("Shot A.png", 30, false)], records: ["Shot A.png": record])
    #expect(try tools.latestJSON(kind: .image)["summary"] == .array(record.summaryLines.map(JSONValue.string)))
}

@Test func theCommandLineFailsWhereTheToolsWouldSaySo() throws {
    #expect(throws: ShotCommandError.noInput(#"No capture matches "shot zebra". The nearest are "Shot B.png", "Shot A (2).png", "Recording C.mp4"."#)) {
        try captures.getJSON("shot zebra")
    }
    let empty = tools(in: folder, [])
    #expect(throws: ShotCommandError.noInput("No recordings in /shots yet.")) { try empty.latestJSON(kind: .video) }
    #expect(throws: ShotCommandError.noInput("No captures in /shots yet.")) { try empty.getJSON("  ") }
    #expect(try empty.listJSON(limit: nil, since: nil) == .array([]))
    #expect(throws: ShotCommandError.usage("list", "--since soon isn't a date, such as 2026-10-10 or 2026-10-10T14:00, or a span back from now, such as 10m, 2h or 3d")) {
        try captures.listJSON(limit: nil, since: "soon")
    }
}

@Test func theServerRunsTheToolsOverJSONRPC() async {
    let server = captures.server(version: "1.2.3")
    let list = await server.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    #expect(list?.contains(#""name":"get_capture""#) == true)
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"Latest-Capture","arguments":{"kind":"video"}}}"#)
    #expect(reply?.contains(#""data":"PREVIEW:Recording C.mp4""#) == true)
    #expect(reply?.contains(#""isError":false"#) == true)
}

@Test func theServerLeavesOutTheToolsThePlatformCantRun() async {
    var tools = captures
    tools.unavailable = [AgentTools.findText]
    let server = tools.server(version: "1.2.3")
    #expect(server.tools.map(\.name) == AgentTools.definitions.map(\.name).filter { $0 != "find_text" })
    let list = await server.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    #expect(list?.contains(#""name":"find_text""#) == false)
}

/// Tools over `captures` whose `run` records what it was asked and answers with a made-up file beside the input.
private func making(_ ran: Ran, fail: ShotCommandError? = nil) -> AgentTools {
    var tools = captures
    tools.run = { command, origin throws(ShotCommandError) in
        ran.commands.append(command)
        ran.origins.append(origin)
        if let fail { throw fail }
        return .object(["path": .string("/shots/new.png"), "bytes": .number(10)])
    }
    return tools
}

private final class Ran: @unchecked Sendable {
    var commands: [ShotCommand] = []
    var origins: [ProjectOrigin] = []
}

@Test func annotateDrawsOnTheNewestScreenshotByDefaultAndShowsTheResult() async throws {
    let ran = Ran()
    let marks: JSONValue = .array([.object(["type": .string("rectangle"), "rect": .array([1, 2, 3, 4].map(JSONValue.number))])])
    let result = await making(ran).call("annotate", .object(["annotations": marks]))
    #expect(result.isError == false)
    #expect(ran.commands == [.annotate(ShotCommand.AnnotateOptions(input: "/shots/Shot B.png", marks: .marks([CaptureMark(type: "rectangle", rect: [1, 2, 3, 4])])))])
    #expect(result.content.first == .image(data: "PREVIEW:new.png", mimeType: "image/jpeg"))
    #expect(texts(result).last == "Saved as a new file beside Shot B.png; the original is unchanged.")
}

@Test func aBadMarkIsAnErrorNamingIt() async {
    let ran = Ran()
    let marks: JSONValue = .array([.object(["type": .string("rectangle"), "rect": .array([1, 2, 3, 4].map(JSONValue.number))]), .object(["type": .string("squiggle")])])
    let result = await making(ran).call("annotate", .object(["annotations": marks]))
    #expect(result.isError)
    #expect(texts(result).first?.hasPrefix("mark 1 (squiggle): unknown type") == true)
    #expect(ran.commands.isEmpty)
    #expect(await making(ran).call("annotate", .object([:])).isError)
}

@Test func redactHidesEveryKindOfPrivateTextByDefaultAndShowsTheResult() async {
    let ran = Ran()
    let result = await making(ran).call("redact", .object([:]))
    #expect(result.isError == false)
    #expect(ran.commands == [.redact(ShotCommand.RedactOptions(input: "/shots/Shot B.png", detect: [.email, .token, .card]))])
    #expect(result.content.first == .image(data: "PREVIEW:new.png", mimeType: "image/jpeg"))
    #expect(texts(result).last == "Saved as a new file beside Shot B.png; the original is unchanged.")
}

@Test func redactTakesItsKindsRectsAndStyle() async {
    let ran = Ran()
    let tools = making(ran)
    let rect: JSONValue = .array([10, 20, 30, 40].map(JSONValue.number))
    #expect(await tools.call("redact", .object(["name": .string("Shot A"), "rects": .array([rect]), "style": .string("Blur")])).isError == false)
    #expect(await tools.call("redact", .object(["rects": .array([rect]), "detect": .array([.string("card")])])).isError == false)
    #expect(await tools.call("redact", .object(["detect": .string("email,token")])).isError == false)
    #expect(ran.commands == [
        .redact(ShotCommand.RedactOptions(input: "/shots/Shot A (2).png", rects: [[10, 20, 30, 40]], style: .blur)),
        .redact(ShotCommand.RedactOptions(input: "/shots/Shot B.png", rects: [[10, 20, 30, 40]], detect: [.card])),
        .redact(ShotCommand.RedactOptions(input: "/shots/Shot B.png", detect: [.email, .token])),
    ])
}

@Test func redactRefusesWhatMakesNoSense() async {
    let ran = Ran()
    let tools = making(ran)
    for arguments: [String: JSONValue] in [
        ["detect": .array([.string("phone")])],
        ["detect": .array([])],
        ["rects": .array([.array([1, 2, 0, 4].map(JSONValue.number))])],
        ["rects": .array([.array([1, 2, 3].map(JSONValue.number))])],
        ["rects": .string("1,2,3,4")],
        ["style": .string("smudge")],
    ] {
        #expect(await tools.call("redact", .object(arguments)).isError, "\(arguments)")
    }
    #expect(await tools.call("redact", .object(["name": .string("Recording C")])).isError)
    #expect(ran.commands.isEmpty)
}

@Test func redactWithNothingToHideSaysNoFileWasWritten() async {
    var tools = captures
    tools.run = { _, _ throws(ShotCommandError) in
        .object(["path": .string("/shots/Shot B.png"), "found": .array([]), "unchanged": .bool(true)])
    }
    let result = await tools.call("redact", .object([:]))
    #expect(result.isError == false)
    #expect(result.content.count == 2)
    #expect(texts(result).last == "Found nothing to hide in Shot B.png, so no file was written.")
}

@Test func editImageEditsTheNewestScreenshotAndPlacesOnlyCaptures() async {
    let ran = Ran()
    let tools = making(ran)
    let result = await tools.call("edit_image", .object([
        "pad": .number(40), "background": .string("white"), "style": .object(["shadow": .string("soft")]),
        "place": .array([.object(["path": .string("Shot A (2)"), "at": .array([.number(0), .number(0)])])]),
    ]))
    #expect(result.isError == false)
    let edit = ImageEdit(pad: [40, 40, 40, 40], background: "white", style: ImageEdit.Style(shadow: "soft"), place: [ImageEdit.Placement(path: "/shots/Shot A (2).png", at: [0, 0])])
    #expect(ran.commands == [.edit(ShotCommand.EditOptions(input: "/shots/Shot B.png", spec: .edit(edit)))])
    #expect(result.content.first == .image(data: "PREVIEW:new.png", mimeType: "image/jpeg"))
    #expect(texts(result).last == "Saved as a new file beside Shot B.png; the original is unchanged.")

    // A file that isn't a capture, a recording, or a bad field is refused before anything runs.
    let outside = await tools.call("edit_image", .object(["place": .array([.object(["path": .string("/etc/passwd")])])]))
    #expect(texts(outside).first?.hasPrefix("place[0]: no screenshot in /shots matches") == true)
    #expect(await tools.call("edit_image", .object(["place": .array([.object(["path": .string("Recording C")])])])).isError)
    let bad = await tools.call("edit_image", .object(["name": .string("Shot A"), "style": .object(["shadow": .string("huge")])]))
    #expect(texts(bad).first == "style.shadow must be soft, float, contact, glow or none")
    #expect(await tools.call("edit_image", .object([:])).isError)
    #expect(await tools.call("edit_image", .object(["name": .string("Recording C"), "pad": .number(4)])).isError)
    #expect(ran.commands.count == 1)
}

@Test func editVideoEditsTheNewestRecordingAndAppendsOnlyRecordings() async {
    let ran = Ran()
    let tools = making(ran)
    let result = await tools.call("edit_video", .object([
        "keep": .array([.array([.number(1), .number(4)])]), "speed": .number(2), "mute": .bool(true),
        "append": .array([.string("Recording C")]), "format": .string("gif"), "maxBytes": .number(10_000_000),
    ]))
    #expect(result.isError == false)
    let edit = VideoEdit(keep: [[1, 4]], speed: 2, mute: true, append: ["/shots/Recording C.mp4"], format: .gif, maxBytes: 10_000_000)
    #expect(ran.commands == [.edit(ShotCommand.EditOptions(input: "/shots/Recording C.mp4", spec: .video(edit)))])
    #expect(texts(result).last == "Saved as a new file beside Recording C.mp4; the original is unchanged.")

    let screenshot = await tools.call("edit_video", .object(["append": .array([.string("Shot B")])]))
    #expect(texts(screenshot).first?.hasPrefix("append[0]: no recording in /shots matches") == true)
    let bad = await tools.call("edit_video", .object(["speed": .number(9)]))
    #expect(texts(bad).first == "speed must be a number from 0.25 to 4, such as 2 for twice as fast")
    #expect(await tools.call("edit_video", .object(["name": .string("Shot B"), "mute": .bool(true)])).isError)
    #expect(ran.commands.count == 1)
}

@Test func whatAToolMakesSaysTheClientAndToolAskedForIt() async {
    let ran = Ran()
    let client = MCPServer.Client(name: "claude-code", version: "2.1.0")
    _ = await making(ran).call("trim_video", .object(["start": .number(1), "end": .number(2)]), client: client)
    _ = await making(ran).call("annotate", .object(["annotations": .array([])]))
    #expect(ran.origins.map(\.via) == [.mcp, .mcp])
    #expect(ran.origins.map(\.client) == ["claude-code", nil])
    #expect(ran.origins.map(\.action) == ["trim_video", "annotate"])
}

@Test func capturesAndRecordingsAskedForCarryTheirOriginButStopsAndMarksDont() async {
    let asked = Asked()
    let client = MCPServer.Client(name: "cursor", version: nil)
    _ = await capturing(asked, answer: .success(["path": .string("/shots/Shot C.png")])).call("capture_window", .object(["window": .string("a")]), client: client)
    let tools = recording(asked, answer: saved)
    _ = await tools.call("record_window", .object(["window": .string("a"), "duration": .number(2)]), client: client)
    _ = await tools.call("record_window", .object(["action": .string("stop")]), client: client)
    _ = await tools.call("record_window", .object(["action": .string("mark"), "label": .string("here")]), client: client)
    #expect(asked.origins.map { $0?.action } == ["capture_window", "record_window", nil, nil])
    #expect(asked.origins.map { $0?.client } == ["cursor", "cursor", nil, nil])
    #expect(asked.origins.allSatisfy { $0 == nil || $0?.via == .mcp })
}

@Test func gifAndTrimNeedARecordingAndPassTheirTimes() async {
    let ran = Ran()
    let tools = making(ran)
    #expect(await tools.call("make_gif", .object(["start": .number(1), "fps": .number(99), "width": .string("400")])).isError == false)
    #expect(await tools.call("trim_video", .object(["name": .string("recording c"), "start": .number(1), "end": .number(2.5)])).isError == false)
    #expect(ran.commands == [
        .gif(ShotCommand.GIFOptions(input: "/shots/Recording C.mp4", fps: 30, width: 400, start: 1)),
        .trim(ShotCommand.TrimOptions(input: "/shots/Recording C.mp4", start: 1, end: 2.5)),
    ])
    let screenshot = await tools.call("make_gif", .object(["name": .string("Shot B")]))
    #expect(screenshot.isError)
    #expect(texts(screenshot).first == "Shot B.png is a screenshot; make_gif needs a recording.")
    #expect(await tools.call("trim_video", .object(["start": .number(3), "end": .number(2)])).isError)
    #expect(ran.commands.count == 2)
}

@Test func compareRunsADiffOfTwoScreenshotsAndShowsIt() async {
    let ran = Ran()
    let result = await making(ran).call("compare", .object(["a": .string("shot a"), "b": .string("/shots/Shot B.png"), "threshold": .number(5)]))
    #expect(result.isError == false)
    // "shot a" finds the newest version of Shot A, which has the markup.
    #expect(ran.commands == [.diff(ShotCommand.DiffOptions(a: "/shots/Shot A (2).png", b: "/shots/Shot B.png", threshold: 1))])
    #expect(result.content.first == .image(data: "PREVIEW:new.png", mimeType: "image/jpeg"))
    #expect(texts(result).last == "Saved the diff as a new file beside Shot B.png; neither screenshot is changed.")
}

@Test func compareNeedsTwoScreenshotsInTheFolder() async {
    let ran = Ran()
    let tools = making(ran)
    let missing = await tools.call("compare", .object(["a": .string("Shot A")]))
    #expect(missing.isError)
    #expect(texts(missing) == ["compare needs a and b: the screenshots before and after, each a path or words from its name."])
    let video = await tools.call("compare", .object(["a": .string("Shot A"), "b": .string("Recording C")]))
    #expect(texts(video) == ["Recording C.mp4 is a recording; compare needs two screenshots. get_frames shows a recording's frames."])
    #expect(await tools.call("compare", .object(["a": .string("/etc/passwd"), "b": .string("Shot B")])).isError)
    #expect(ran.commands.isEmpty)
}

@Test func onlyCapturesInTheFolderCanBeNamed() async {
    let ran = Ran()
    let result = await making(ran).call("annotate", .object(["path": .string("/etc/passwd"), "annotations": .array([])]))
    #expect(result.isError)
    #expect(ran.commands.isEmpty)
}

@Test func aFailedCommandIsAnErrorWithItsMessage() async {
    let result = await making(Ran(), fail: .data("rect 1 is off the image")).call("trim_video", .object(["start": .number(0), "end": .number(1)]))
    #expect(result.isError)
    #expect(texts(result) == ["rect 1 is off the image"])
}

@Test func getFramesReadsTheNewestRecordingAndClampsTheCount() async {
    let asked = Ran()
    var tools = captures
    tools.frames = { entry, count throws(ShotCommandError) in
        asked.commands.append(.frames(ShotCommand.FramesOptions(input: entry.url.path, count: count)))
        return [.text("t=0.0s of 1.0s"), .image(data: "FRAME", mimeType: "image/jpeg")]
    }
    let result = await tools.call("get_frames", .object(["count": .number(50)]))
    #expect(result.isError == false)
    #expect(asked.commands == [.frames(ShotCommand.FramesOptions(input: "/shots/Recording C.mp4", count: 12))])
    #expect(texts(result) == ["Recording C.mp4, at /shots/Recording C.mp4:", "t=0.0s of 1.0s"])
    let screenshot = await tools.call("get_frames", .object(["name": .string("Shot B")]))
    #expect(screenshot.isError)
    #expect(asked.commands.count == 1)
}

/// The requests the app was sent, and apart from them, since each is dated, the origins they carried.
private final class Asked: @unchecked Sendable {
    var requests: [AgentRequest] = []
    var origins: [ProjectOrigin?] = []
}

private func capturing(_ asked: Asked, answer: Result<[String: JSONValue], ShotCommandError>) -> AgentTools {
    var tools = captures
    tools.agent = { request throws(ShotCommandError) in
        var request = request
        asked.origins.append(request.origin)
        request.origin = nil
        asked.requests.append(request)
        return try answer.get()
    }
    tools.record = { entry in
        CaptureRecord(kind: "image", created: now, size: CaptureRecord.Size(width: 10, height: 10), scale: 2, source: CaptureRecord.Source(mode: "window", app: "Simulator", windowTitle: entry.name))
    }
    return tools
}

@Test func captureWindowAsksTheAppAndShowsWhatItSaved() async {
    let asked = Asked()
    let saved: [String: JSONValue] = [
        "path": .string("/shots/Shot C.png"),
        "bytes": .number(1200),
        "window": .object(["app": .string("Simulator"), "title": .string("iPhone 17")]),
    ]
    let result = await capturing(asked, answer: .success(saved)).call("capture_window", .object(["window": .string("simulator")]))
    #expect(result.isError == false)
    #expect(asked.requests == [AgentRequest(.capture, window: "simulator")])
    #expect(result.content.first == .image(data: "PREVIEW:Shot C.png", mimeType: "image/jpeg"))
    let lines = texts(result)
    #expect(lines.first?.contains(#""path" : "/shots/Shot C.png""#) == true)
    #expect(lines.last?.contains("Simulator") == true)
}

@Test func captureWindowNeedsAWindowAndPassesOnTheAppsError() async {
    let asked = Asked()
    let tools = capturing(asked, answer: .failure(.unavailable("Turn on Let agents capture and record")))
    let missing = await tools.call("capture_window", .object(["window": .string("  ")]))
    #expect(missing.isError)
    #expect(asked.requests.isEmpty)
    let off = await tools.call("capture_window", .object(["window": .string("Calculator")]))
    #expect(off.isError)
    #expect(texts(off) == ["Turn on Let agents capture and record"])
}

private func recording(_ asked: Asked, frameCounts: Ran? = nil, answer: [String: JSONValue]) -> AgentTools {
    var tools = capturing(asked, answer: .success(answer))
    tools.frames = { entry, count throws(ShotCommandError) in
        frameCounts?.commands.append(.frames(ShotCommand.FramesOptions(input: entry.url.path, count: count)))
        return [.text("t=0.0s of 3.0s"), .image(data: "FRAME", mimeType: "image/jpeg")]
    }
    return tools
}

private let saved: [String: JSONValue] = ["id": .string("ab12cd34"), "path": .string("/shots/Recording D.mp4"), "duration": .number(3)]

@Test func recordWindowWithADurationWaitsThenShowsSixKeyFrames() async {
    let asked = Asked()
    let counts = Ran()
    let result = await recording(asked, frameCounts: counts, answer: saved).call("record_window", .object(["window": .string("Simulator"), "duration": .number(3)]))
    #expect(result.isError == false)
    #expect(asked.requests == [AgentRequest(.record, window: "Simulator", duration: 3)])
    #expect(counts.commands == [.frames(ShotCommand.FramesOptions(input: "/shots/Recording D.mp4", count: 6))])
    #expect(result.content.last == .image(data: "FRAME", mimeType: "image/jpeg"))
}

@Test func recordWindowWaitsAtMostTwoMinutes() async {
    let asked = Asked()
    let result = await recording(asked, answer: saved).call("record_window", .object(["window": .string("Simulator"), "duration": .number(900)]))
    #expect(asked.requests == [AgentRequest(.record, window: "Simulator", duration: 120)])
    #expect(texts(result).contains { $0.hasPrefix("Recorded 120 seconds") })
}

@Test func recordWindowWithoutADurationGivesAnIDToStopItWith() async {
    let asked = Asked()
    let result = await recording(asked, answer: ["id": .string("ab12cd34")]).call("record_window", .object(["window": .string("Simulator")]))
    #expect(result.isError == false)
    #expect(asked.requests == [AgentRequest(.record, window: "Simulator")])
    #expect(texts(result).last?.contains("action stop and id ab12cd34") == true)
}

@Test func recordWindowStopsByIDOrTheOneInProgress() async {
    let asked = Asked()
    let tools = recording(asked, answer: saved)
    let byID = await tools.call("record_window", .object(["action": .string("stop"), "id": .string("ab12cd34")]))
    _ = await tools.call("record_window", .object(["action": .string("STOP")]))
    #expect(asked.requests == [AgentRequest(.stop, id: "ab12cd34"), AgentRequest(.stop)])
    #expect(byID.content.last == .image(data: "FRAME", mimeType: "image/jpeg"))
}

@Test func recordWindowMarksTheRecordingWithoutStoppingIt() async {
    let asked = Asked()
    let counts = Ran()
    let tools = recording(asked, frameCounts: counts, answer: ["id": .string("ab12cd34"), "time": .number(2.5), "label": .string("tapped Login")])
    let result = await tools.call("record_window", .object(["action": .string("mark"), "label": .string(" tapped Login ")]))
    #expect(result.isError == false)
    _ = await tools.call("record_window", .object(["action": .string("mark"), "label": .string(String(repeating: "a", count: 300)), "id": .string("ab12cd34")]))
    #expect(asked.requests == [AgentRequest(.mark, label: "tapped Login"), AgentRequest(.mark, id: "ab12cd34", label: String(repeating: "a", count: 200))])
    #expect(counts.commands.isEmpty)
    #expect(texts(result).first?.contains(#""time" : 2.5"#) == true)
    let unlabelled = await tools.call("record_window", .object(["action": .string("mark")]))
    #expect(unlabelled.isError)
    #expect(asked.requests.count == 2)
}

@Test func recordWindowNeedsAWindowToStartAndAKnownAction() async {
    let asked = Asked()
    let tools = recording(asked, answer: saved)
    #expect(await tools.call("record_window", .object([:])).isError)
    #expect(await tools.call("record_window", .object(["action": .string("pause"), "window": .string("a")])).isError)
    #expect(asked.requests.isEmpty)
}

// MARK: find_text

private let screenText = CaptureText(width: 1200, height: 800, lines: [
    CaptureText.Line(text: "Settings", box: CGRect(x: 20, y: 10, width: 120, height: 30), words: [
        CaptureText.Word(text: "Settings", box: CGRect(x: 20, y: 10, width: 120, height: 30)),
    ]),
    CaptureText.Line(text: "Cancel Save", box: CGRect(x: 900, y: 740, width: 200, height: 30), words: [
        CaptureText.Word(text: "Cancel", box: CGRect(x: 900, y: 740, width: 90, height: 30)),
        CaptureText.Word(text: "Save", box: CGRect(x: 1020, y: 740, width: 80, height: 30)),
    ]),
])

private func reading(_ read: Ran) -> AgentTools {
    var tools = captures
    tools.text = { entry throws(ShotCommandError) in
        read.commands.append(.text(path: entry.url.path))
        return screenText
    }
    return tools
}

private func object(_ result: MCPServer.ToolResult) throws -> [String: JSONValue] {
    let json = try #require(texts(result).first)
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    guard case let .object(object) = value else {
        Issue.record("not an object: \(json)")
        return [:]
    }
    return object
}

private func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> JSONValue {
    .array([x, y, width, height].map(JSONValue.number))
}

@Test func findTextReadsEveryLineOfTheNewestScreenshot() async throws {
    let read = Ran()
    let result = await reading(read).call("find_text", .object([:]))
    #expect(result.isError == false)
    #expect(read.commands == [.text(path: "/shots/Shot B.png")])
    let found = try object(result)
    #expect(found["path"] == .string("/shots/Shot B.png"))
    #expect(found["text"] == .string("Settings\nCancel Save"))
    #expect(found["size"] == .object(["width": .number(1200), "height": .number(800)]))
    // Lines without their words, which would fill an agent's context.
    #expect(found["lines"] == .array([
        .object(["text": .string("Settings"), "box": box(20, 10, 120, 30)]),
        .object(["text": .string("Cancel Save"), "box": box(900, 740, 200, 30)]),
    ]))
}

@Test func findTextWithAQueryGivesOnlyTheMatchingLinesAndWhereTheMatchIs() async throws {
    let read = Ran()
    let result = await reading(read).call("find_text", .object(["path": .string("/shots/Shot A.png"), "query": .string("SAVE")]))
    #expect(read.commands == [.text(path: "/shots/Shot A.png")])
    let found = try object(result)
    #expect(found["query"] == .string("SAVE"))
    #expect(found["lines"] == nil && found["text"] == nil)
    #expect(found["matches"] == .array([
        .object(["text": .string("Cancel Save"), "box": box(900, 740, 200, 30), "match": box(1020, 740, 80, 30)]),
    ]))
}

@Test func findTextWithNoMatchSaysSoAndGivesAllTheText() async throws {
    let result = await reading(Ran()).call("find_text", .object(["query": .string("Delete")]))
    #expect(result.isError == false)
    let found = try object(result)
    #expect(found["matches"] == .array([]))
    #expect(found["text"] == .string("Settings\nCancel Save"))
    #expect(texts(result).last?.contains(#"No line in Shot B.png contains "Delete""#) == true)
}

@Test func findTextRefusesARecordingAndPassesOnAnError() async {
    let read = Ran()
    let recording = await reading(read).call("find_text", .object(["name": .string("Recording C")]))
    #expect(recording.isError)
    #expect(read.commands.isEmpty)
    var failing = captures
    failing.text = { _ throws(ShotCommandError) in throw .data("Couldn't read Shot B.png as an image.") }
    let failed = await failing.call("find_text", .object([:]))
    #expect(failed.isError)
    #expect(texts(failed) == ["Couldn't read Shot B.png as an image."])
}

@Test func waitForCaptureReturnsTheNextCaptureAsLatestCaptureDoes() async {
    let listed = Mutex([AgentCaptures.Entry(url: folder.appendingPathComponent("Shot A.png"), isVideo: false, date: now.addingTimeInterval(-60))])
    var tools = AgentTools(
        folder: folder,
        entries: { listed.withLock { $0 } },
        preview: { entry in [.image(data: "PREVIEW:\(entry.name)", mimeType: "image/jpeg")] },
        now: { now },
        timeZone: utc
    )
    tools.pollInterval = .milliseconds(10)
    let waiting = Task { [tools] in await tools.call("wait_for_capture", .object(["timeout": .number(5)])) }
    try? await Task.sleep(for: .milliseconds(50))
    listed.withLock { $0.append(AgentCaptures.Entry(url: folder.appendingPathComponent("Recording B.mp4"), isVideo: true, date: now)) }
    let result = await waiting.value
    #expect(result.isError == false)
    #expect(result.content.first == .image(data: "PREVIEW:Recording B.mp4", mimeType: "image/jpeg"))
    #expect(texts(result).first?.contains(#""kind" : "video""#) == true)
}

@Test func waitForCaptureSaysWhenNothingCameInTime() async {
    var tools = captures
    tools.pollInterval = .milliseconds(10)
    let result = await tools.call("wait_for_capture", .object(["kind": .string("image"), "timeout": .string("0")]))
    #expect(result.isError == false)
    #expect(texts(result) == ["No new screenshot in /shots after 1 second. Call wait_for_capture again to keep waiting."])
}

@Test func listWindowsAsksTheAppAndGivesItsAnswerAsJSON() async {
    let asked = Asked()
    let windows: [String: JSONValue] = ["windows": .array([.object(["app": .string("Simulator"), "frontmost": .bool(true)])]), "displays": .array([])]
    let result = await capturing(asked, answer: .success(windows)).call("list_windows", .object([:]))
    #expect(result.isError == false)
    #expect(asked.requests == [AgentRequest(.windows)])
    #expect(texts(result).first?.contains(#""app" : "Simulator""#) == true)
    let off = await capturing(Asked(), answer: .failure(.unavailable("Turn on Let agents capture and record"))).call("list_windows", .object([:]))
    #expect(off.isError)
    #expect(texts(off) == ["Turn on Let agents capture and record"])
}

@Test func captureWindowTakesABundleIDADisplayARectAndNoShadow() async {
    let asked = Asked()
    let tools = capturing(asked, answer: .success(["path": .string("/shots/Shot C.png")]))
    _ = await tools.call("capture_window", .object(["bundleID": .string("com.apple.iphonesimulator"), "rect": .array([.number(0), .number(40), .number(390), .string("200")]), "noShadow": .bool(true)]))
    _ = await tools.call("capture_window", .object(["display": .number(2), "waitStable": .number(90)]))
    _ = await tools.call("capture_window", .object(["window": .string("Simulator"), "waitStable": .bool(true)]))
    #expect(asked.requests == [
        AgentRequest(.capture, target: AgentTarget(bundleID: "com.apple.iphonesimulator", rect: [0, 40, 390, 200], noShadow: true)),
        AgentRequest(.capture, target: AgentTarget(display: 2, waitStable: 30)),
        AgentRequest(.capture, target: AgentTarget(window: "Simulator", waitStable: 5)),
    ])
}

@Test func captureWindowRefusesATargetThatDoesntMakeSense() async {
    let asked = Asked()
    let tools = capturing(asked, answer: .success(["path": .string("/shots/Shot C.png")]))
    let both = await tools.call("capture_window", .object(["window": .string("Simulator"), "display": .number(1)]))
    #expect(texts(both) == ["capture_window takes a window or a display, not both."])
    let rect = await tools.call("capture_window", .object(["window": .string("Simulator"), "rect": .array([.number(0), .number(0), .number(10)])]))
    #expect(rect.isError)
    let display = await tools.call("capture_window", .object(["display": .number(1.5)]))
    #expect(display.isError)
    #expect(asked.requests.isEmpty)
}

@Test func recordWindowTakesTheSameTargetsButNeverWaitsToSettle() async {
    let asked = Asked()
    let tools = recording(asked, answer: ["id": .string("ab12cd34")])
    _ = await tools.call("record_window", .object(["display": .number(1), "rect": .array([.number(0), .number(0), .number(800), .number(600)]), "waitStable": .number(3)]))
    #expect(asked.requests == [AgentRequest(.record, target: AgentTarget(display: 1, rect: [0, 0, 800, 600]))])
}

private final class Zooms: @unchecked Sendable {
    var asked: [(name: String, rect: [Double])] = []
}

/// Tools over `captures` whose `zoom` records what it was asked and shows `shown` of a 5120×2880 file.
private func zooming(_ zooms: Zooms, shown: CaptureRecord.Size? = nil, fail: ShotCommandError? = nil) -> AgentTools {
    var tools = captures
    tools.zoom = { entry, rect throws(ShotCommandError) in
        zooms.asked.append((entry.name, rect))
        if let fail { throw fail }
        let region = CropRegion.clamped(rect, width: 5120, height: 2880) ?? []
        return AgentTools.Zoomed(
            image: .image(data: "ZOOM", mimeType: "image/jpeg"), region: region,
            shown: shown ?? CaptureRecord.Size(width: region[2], height: region[3]), file: CaptureRecord.Size(width: 5120, height: 2880)
        )
    }
    return tools
}

private func rect(_ values: Double...) -> JSONValue {
    .array(values.map(JSONValue.number))
}

@Test func zoomShowsPartOfTheNewestScreenshotAtFullResolution() async {
    let zooms = Zooms()
    let result = await zooming(zooms).call("zoom", .object(["rect": rect(100, 200, 300, 40)]))
    #expect(result.isError == false)
    #expect(zooms.asked.map(\.name) == ["Shot B.png"])
    #expect(zooms.asked.map(\.rect) == [[100, 200, 300, 40]])
    #expect(result.content.first == .image(data: "ZOOM", mimeType: "image/jpeg"))
    #expect(texts(result) == ["This is [100, 200, 300, 40] of Shot B.png, which is 5120×2880 pixels, at full resolution: add 100 to x and 200 to y for the file's pixels."])
}

@Test func zoomSaysWhenItScaledOrCutTheRect() async {
    let zooms = Zooms()
    let result = await zooming(zooms, shown: CaptureRecord.Size(width: 1568, height: 882)).call("zoom", .object(["name": .string("shot a"), "rect": rect(-10.5, 0, 5200, 2880)]))
    #expect(zooms.asked.map(\.name) == ["Shot A (2).png"])
    #expect(texts(result) == [
        "This is [0, 0, 5120, 2880] of Shot A (2).png, which is 5120×2880 pixels, scaled to 1568×882 to fit: divide by 0.306, then add 0 to x and 0 to y for the file's pixels. Zoom into a smaller part to see it at full resolution. The rect asked for was -10.5,0,5200,2880, cut to whole pixels within the image.",
    ])
}

@Test func zoomNeedsARectAndAScreenshotInTheFolder() async {
    let zooms = Zooms()
    let tools = zooming(zooms)
    let missing = await tools.call("zoom", .object([:]))
    #expect(missing.isError)
    #expect(texts(missing) == ["zoom needs rect: [x, y, width, height] in the file's pixels from the top left, with a width and height above 0."])
    #expect(await tools.call("zoom", .object(["rect": rect(1, 2, 0, 4)])).isError)
    let video = await tools.call("zoom", .object(["name": .string("Recording C"), "rect": rect(1, 2, 3, 4)]))
    #expect(texts(video) == ["Recording C.mp4 is a recording; zoom shows part of a screenshot. get_frames shows a recording's frames."])
    #expect(await tools.call("zoom", .object(["path": .string("/tmp/elsewhere.png"), "rect": rect(1, 2, 3, 4)])).isError)
    #expect(zooms.asked.isEmpty)
    let failed = await zooming(zooms, fail: .data("off the image")).call("zoom", .object(["rect": rect(1, 2, 3, 4)]))
    #expect(failed.isError)
    #expect(texts(failed) == ["off the image"])
}

@Test func askForCaptureAsksThePersonWithThePromptAndShowsWhatTheyPicked() async {
    let asked = Asked()
    let saved: [String: JSONValue] = ["path": .string("/shots/Shot C.png"), "window": .object(["area": .bool(true)])]
    let tools = capturing(asked, answer: .success(saved))
    let result = await tools.call("ask_for_capture", .object(["prompt": .string("Select the\nbroken toolbar"), "timeout": .number(900)]), client: MCPServer.Client(name: "claude-code", version: "1"))
    #expect(result.isError == false)
    var expected = AgentRequest(.pick, duration: 120)
    expected.prompt = "Select the broken toolbar"
    #expect(asked.requests == [expected])
    #expect(asked.origins.first??.client == "claude-code")
    #expect(asked.origins.first??.action == "ask_for_capture")
    #expect(result.content.first == .image(data: "PREVIEW:Shot C.png", mimeType: "image/jpeg"))
    _ = await tools.call("ask_for_capture", .object([:]))
    #expect(asked.requests.last == AgentRequest(.pick, duration: 60))
}

@Test func askForCaptureSaysWhenThePersonCancelsAndRefusesALongPrompt() async {
    let asked = Asked()
    let tools = capturing(asked, answer: .failure(.noInput("The user cancelled the selection.")))
    let cancelled = await tools.call("ask_for_capture", .object(["prompt": .string("Select it")]))
    #expect(cancelled.isError)
    #expect(texts(cancelled) == ["The user cancelled the selection."])
    let long = await tools.call("ask_for_capture", .object(["prompt": .string(String(repeating: "a", count: 101))]))
    #expect(long.isError)
    #expect(asked.requests.count == 1)
}
