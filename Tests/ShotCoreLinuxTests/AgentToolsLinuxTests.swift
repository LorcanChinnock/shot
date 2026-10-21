import Foundation
import Testing
@testable import ShotCoreLinux

private let canvas = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/canvas")

/// A capture folder holding `base.png` as a screenshot and an empty recording, and a project store beside it.
private func captures() throws -> (folder: URL, projects: ProjectStore, screenshot: URL) {
    let root = try temporaryFolder()
    let folder = root.appendingPathComponent("Shot", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let screenshot = folder.appendingPathComponent("Shot 2026-10-20 at 09.00.00.png")
    try FileManager.default.copyItem(at: canvas.appendingPathComponent("base.png"), to: screenshot)
    try Data().write(to: folder.appendingPathComponent("Shot 2026-10-20 at 08.00.00.mov"))
    return (folder, ProjectStore(folder: root.appendingPathComponent("Projects", isDirectory: true)), screenshot)
}

private func text(_ result: MCPServer.ToolResult) -> String {
    result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined(separator: "\n")
}

/// The JSON a tool gave about the file it made.
private func made(_ result: MCPServer.ToolResult) throws -> JSONValue {
    let json = try #require(result.content.compactMap { if case let .text(text) = $0, text.hasPrefix("{") { text } else { nil } }.first, "\(text(result))")
    return try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

@Test func theToolsThatRecordOrPickAnswerThatTheyreNotOnLinuxYet() async {
    let tools = AgentTools.live(folder: URL(fileURLWithPath: "/shots"))
    #expect(tools.server(version: "1").tools.map(\.name) == AgentTools.definitions.map(\.name).filter { $0 != AgentTools.findText })
    for name in Doctor.notOnLinuxYetTools {
        let result = await tools.call(name, .object([:]))
        #expect(result == MCPServer.ToolResult(content: [.text("\(name): not on Linux yet")], isError: true))
    }
}

@Test func anMCPSessionOnLinuxAnnotatesAScreenshotAndReadsItBack() async throws {
    let (folder, projects, screenshot) = try captures()
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    let server = AgentTools.live(folder: folder, projects: projects).server(version: "1")

    let hello = try #require(await server.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test","version":"1"}}}"#))
    #expect(hello.contains("\"serverInfo\""))
    let list = try JSONDecoder().decode(JSONValue.self, from: Data(try #require(await server.respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)).utf8))
    guard case let .array(listed)? = list["result"]?["tools"] else {
        Issue.record("no tools in \(list)")
        return
    }
    let names: [String] = listed.compactMap { $0["name"]?.string }
    #expect(names.contains(AgentTools.annotate))

    let call = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"annotate","arguments":{"annotations":[{"type":"arrow","from":[10,10],"to":[120,90],"color":"blue"}]}}}"#
    let reply = try JSONDecoder().decode(JSONValue.self, from: Data(try #require(await server.respond(to: call)).utf8))
    #expect(reply["result"]?["isError"] != .bool(true), "\(reply)")
    guard case let .array(content)? = reply["result"]?["content"] else {
        Issue.record("no content in \(reply)")
        return
    }
    #expect(content.first?["type"] == .string("image"))
    #expect(content.first?["mimeType"] == .string("image/jpeg"))
    let written = try #require(content.compactMap { $0["text"]?.string }.first { $0.hasPrefix("{") })
    let path = try #require(try JSONDecoder().decode(JSONValue.self, from: Data(written.utf8))["path"]?.string)
    #expect(URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
    #expect(path != screenshot.path)

    let tools = AgentTools.live(folder: folder, projects: projects)
    let read = await tools.call(AgentTools.getCapture, .object(["path": .string(path)]))
    #expect(read.isError != true)
    #expect(read.content.contains { if case .image(_, "image/jpeg") = $0 { true } else { false } })
    #expect(text(read).contains("arrow"), "\(text(read))")
}

@Test func theImageToolsRunOnLinux() async throws {
    let (folder, projects, screenshot) = try captures()
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    let tools = AgentTools.live(folder: folder, projects: projects)

    let latest = await tools.call(AgentTools.latestCapture, .object([:]))
    #expect(text(latest).contains(screenshot.lastPathComponent))
    let listed = await tools.call(AgentTools.listCaptures, .object([:]))
    #expect(text(listed).contains("08.00.00.mov") && text(listed).contains("09.00.00.png"))
    let zoomed = await tools.call(AgentTools.zoom, .object(["rect": .array([10, 20, 60, 40].map { .number($0) })]))
    #expect(zoomed.isError != true, "\(text(zoomed))")
    #expect(zoomed.content.contains { if case .image = $0 { true } else { false } })

    let redacted = await tools.call(AgentTools.redact, .object(["rects": .array([.array([10, 10, 50, 30].map { .number($0) })]), "style": .string("blur")]))
    #expect(redacted.isError != true, "\(text(redacted))")
    let byText = await tools.call(AgentTools.redact, .object(["detect": .array([.string("email")])]))
    #expect(byText.isError == true)
    #expect(text(byText).contains("needs a Mac"))

    let annotated = try made(await tools.call(AgentTools.annotate, .object([
        "path": .string(screenshot.path), "annotations": .array([.object(["type": .string("rectangle"), "rect": .array([20, 20, 60, 40].map { .number($0) })])]),
    ])))
    // A later edit reopens the annotation from its project, so it stays a layer under the new mark.
    let edited = try made(await tools.call(AgentTools.editImage, .object([
        "path": .string(try #require(annotated["path"]?.string)), "pad": .number(10), "background": .string("white"),
        "marks": .array([.object(["type": .string("arrow"), "from": .array([.number(5), .number(5)]), "to": .array([.number(90), .number(70)])])]),
    ])))
    #expect(edited["layers"].map { layers in
        guard case let .array(items) = layers else { return [] }
        return items.compactMap { $0["type"]?.string }
    } == ["rectangle", "arrow"])
    #expect(edited["size"] == .object(["width": .number(180), "height": .number(140)]))
    #expect(projects.entry(for: URL(fileURLWithPath: try #require(edited["path"]?.string)))?.origin.action == AgentTools.editImage)

    let compared = await tools.call(AgentTools.compare, .object(["a": .string(screenshot.path), "b": .string(try #require(annotated["path"]?.string))]))
    #expect(compared.isError != true, "\(text(compared))")
    #expect(text(compared).contains("\"regions\""))
}

@Test func theCommandsThatRecordOrPickAnswerThatTheyreNotOnLinuxYet() async throws {
    let (folder, _, screenshot) = try captures()
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    let commands: [ShotCommand] = [try ShotCommand.parse(["record", "--display", "1"]), .pick(ShotCommand.PickOptions())]
    for command in commands {
        await #expect(throws: ShotCommandError.notOnLinuxYet, "\(command.name)") {
            try await ShotCommands.run(command)
        }
    }
    await #expect(throws: ShotCommandError.unavailable("reading the text in an image needs a Mac")) {
        try await ShotCommands.run(.text(path: screenshot.path))
    }
    let info = try await ShotCommands.run(.info(path: screenshot.path))
    #expect(info["kind"] == .string("image"))
    #expect(info["size"] == .object(["width": .number(160), "height": .number(120)]))
}

@Test(.enabled(if: hasFFmpeg, "ffmpeg isn't installed"))
func theVideoToolsRunOnLinux() async throws {
    let (folder, projects, _) = try captures()
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    let recording = folder.appendingPathComponent("Shot 2026-10-20 at 10.00.00.mp4")
    try FileManager.default.copyItem(at: timed, to: recording)
    let marks = folder.deletingLastPathComponent().appendingPathComponent("recording-marks.json")
    try RecordingMarks.save([RecordingMark(time: 1.2, label: "Saved")], for: recording, in: marks)
    let tools = AgentTools.live(folder: folder, marks: marks, projects: projects)

    let preview = await tools.call(AgentTools.getCapture, .object(["name": .string("10.00.00")]))
    #expect(preview.content.contains { if case .image(_, "image/jpeg") = $0 { true } else { false } })
    #expect(text(preview).contains("A recording 2.0 seconds long, 160×120, with sound. The image is its frame at 1.0 seconds."), "\(text(preview))")

    // By path, since the empty recording beside it is as new.
    let frames = await tools.call(AgentTools.getFrames, .object(["path": .string(recording.path), "count": .number(3)]))
    #expect(frames.isError != true, "\(text(frames))")
    #expect(frames.content.filter { if case .image = $0 { true } else { false } }.count >= 2)
    #expect(text(frames).contains(#"marked "Saved""#), "\(text(frames))")
    #expect(text(frames).contains("Its sound isn't transcribed: that needs a Mac."))

    let gif = try made(await tools.call(AgentTools.makeGIF, .object(["path": .string(recording.path), "start": .number(0.5), "end": .number(1.5), "fps": .number(10), "width": .number(80)])))
    #expect(gif["frames"] == .number(10) && gif["size"] == .object(["width": .number(80), "height": .number(60)]), "\(gif)")
    #expect(try #require(gif["path"]?.string).hasSuffix(".gif"))

    let trimmed = try made(await tools.call(AgentTools.trimVideo, .object(["path": .string(recording.path), "start": .number(0.5), "end": .number(1.5)])))
    #expect(abs((trimmed["duration"]?.number ?? 0) - 1) < 0.1, "\(trimmed)")

    let edited = try made(await tools.call(AgentTools.editVideo, .object([
        "path": .string(recording.path), "cut": .array([.array([.number(0.5), .number(1)])]),
        "marks": .array([.object(["start": .number(0), "type": .string("arrow"), "from": .array([.number(10), .number(10)]), "to": .array([.number(90), .number(70)])])]),
    ])))
    #expect(abs((edited["duration"]?.number ?? 0) - 1.5) < 0.1, "\(edited)")
    let path = URL(fileURLWithPath: try #require(edited["path"]?.string))
    #expect(projects.entry(for: path)?.origin.action == AgentTools.editVideo)
}
