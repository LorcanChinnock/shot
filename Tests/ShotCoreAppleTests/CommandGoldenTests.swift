import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// The command goldens ShotCoreLinuxTests' CommandParityTests runs on Linux and compares: each case in
// Tests/Fixtures/commands/cases.json is a `shot` command line run over the canvas goldens' `base.png`, and `<name>.png`
// and `<name>.json` are what it wrote on a Mac and what it and `info` on its output printed, with paths, sizes in
// bytes, dates and IDs masked.
//
// Run with SHOT_WRITE_GOLDENS=1 to write them again after a change to a command, and check the new PNGs by eye.
// Otherwise this checks they're still what the Mac writes.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/commands")
private let canvas = folder.deletingLastPathComponent().appendingPathComponent("canvas")

private struct Case: Codable, Sendable, CustomTestStringConvertible {
    var name: String
    var args: [String]
    var testDescription: String { name }
}

private func cases() throws -> [Case] {
    try JSONDecoder().decode([Case].self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
}

@Test(arguments: try cases())
private func theCommandWritesAndPrintsItsGolden(_ test: Case) async throws {
    let work = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    for name in ["base.png", "lines.png"] {
        try FileManager.default.copyItem(at: canvas.appendingPathComponent(name), to: work.appendingPathComponent(name))
    }
    let out = work.appendingPathComponent("\(test.name).png")
    let args = test.args.map {
        $0.replacingOccurrences(of: "{base}", with: work.appendingPathComponent("base.png").path)
            .replacingOccurrences(of: "{lines}", with: work.appendingPathComponent("lines.png").path)
            .replacingOccurrences(of: "{fixtures}", with: folder.path)
            .replacingOccurrences(of: "{out}", with: out.path)
    }
    let result = try await ShotCommands.run(try ShotCommand.parse(args))
    let info = try await ShotCommands.run(.info(path: out.path))
    let printed = ShotCommand.json(.object(["result": masked(result), "info": masked(info)]))
    if ProcessInfo.processInfo.environment["SHOT_WRITE_GOLDENS"] == "1" {
        try printed.write(to: folder.appendingPathComponent("\(test.name).json"), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(test.name).png"))
        try FileManager.default.copyItem(at: out, to: folder.appendingPathComponent("\(test.name).png"))
        return
    }
    #expect(printed == (try String(contentsOf: folder.appendingPathComponent("\(test.name).json"), encoding: .utf8)))
    let codec = ImageIOCodec()
    let wrote = try #require(codec.decode(fileAt: out))
    let golden = try #require(codec.decode(fileAt: folder.appendingPathComponent("\(test.name).png")))
    #expect(wrote.width == golden.width && wrote.height == golden.height)
    let changed = (0 ..< wrote.width * wrote.height).filter { pixel in
        (0 ..< 4).contains { abs(Int(wrote.pixels[pixel * 4 + $0]) - Int(golden.pixels[pixel * 4 + $0])) > 2 }
    }
    // Core Text antialiases the system font a little differently from one macOS release to the next, as
    // CanvasGoldenTests allows for.
    let allowed = test.name == "annotateText" ? wrote.width * wrote.height * 3 / 100 : 0
    #expect(changed.count <= allowed, "\(test.name).png is stale: run with SHOT_WRITE_GOLDENS=1")
}

/// `value` without what changes from run to run, or between a Mac and Linux: paths are their file names, and sizes in
/// bytes, dates and IDs are left out. A text's box is measured in another font on Linux, so only where it starts is kept.
private func masked(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .object(object):
        var kept: [String: JSONValue] = [:]
        for (key, value) in object where !["bytes", "created", "id"].contains(key) {
            kept[key] = masked(value)
        }
        if object["type"] == .string("text"), case let .array(rect)? = object["rect"], rect.count == 4 {
            kept["rect"] = .array(Array(rect.prefix(2)))
        }
        return .object(kept)
    case let .array(items):
        return .array(items.map(masked))
    case let .string(text) where text.hasPrefix("/"):
        return .string(URL(fileURLWithPath: text).lastPathComponent)
    default:
        return value
    }
}
