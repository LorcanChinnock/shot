import Foundation
import Testing
@testable import ShotCoreLinux

// Each case in Tests/Fixtures/commands/cases.json run on Linux, through PNGJPEGCodec and CairoCanvas, and compared with
// what ShotCoreAppleTests' CommandGoldenTests wrote on a Mac: the JSON it and `info` on its output print, field by field
// with paths, sizes in bytes, dates and IDs masked, and the image it wrote, within each case's limits as
// CairoGoldenTests compares the canvas goldens. Set SHOT_CAIRO_GOLDENS to a folder to write what Linux wrote there, to
// look at.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/commands")
private let canvas = folder.deletingLastPathComponent().appendingPathComponent("canvas")

private struct Case: Codable, Sendable {
    var name: String
    var args: [String]
}

/// How far a channel may differ before its pixel counts as different, of 255.
private let tolerance = 16

/// A case, the size of the blocks compared, the share of them that may differ by more than `tolerance`, and how far any
/// channel may differ, as CairoGoldenTests' limits for what each draws.
private let limits: [(name: String, block: Int, share: Double, worst: Int)] = [
    ("annotate", 1, 0.005, 24),
    // In DejaVu Sans, where the Mac draws San Francisco.
    ("annotateText", 20, 0.1, 100),
    ("redactPixelate", 1, 0.005, 16),
    ("redactBlur", 1, 0.005, 16),
    ("crop", 1, 0, 0),
    // The dimmed copy, rounded a level apart.
    ("diff", 1, 0, 1),
    // A shadow, and a picture placed at under a third of its size, whose thinnest lines Cairo's filter and CoreGraphics'
    // resample onto pixels a little apart.
    ("edit", 1, 0.01, 80),
]

@Test func everyCommandCaseHasLimits() throws {
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
    #expect(cases.map(\.name) == limits.map(\.name))
}

@Test(arguments: limits)
func theCommandWritesAndPrintsWhatItDoesOnAMac(name: String, block: Int, share maxShare: Double, worst maxWorst: Int) async throws {
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
    let test = try #require(cases.first { $0.name == name })
    let work = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    for file in ["base.png", "lines.png"] {
        try FileManager.default.copyItem(at: canvas.appendingPathComponent(file), to: work.appendingPathComponent(file))
    }
    let out = work.appendingPathComponent("\(name).png")
    let args = test.args.map {
        $0.replacingOccurrences(of: "{base}", with: work.appendingPathComponent("base.png").path)
            .replacingOccurrences(of: "{lines}", with: work.appendingPathComponent("lines.png").path)
            .replacingOccurrences(of: "{fixtures}", with: folder.path)
            .replacingOccurrences(of: "{out}", with: out.path)
    }
    let result = try await ShotCommands.run(try ShotCommand.parse(args))
    let info = try await ShotCommands.run(.info(path: out.path))
    let golden = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: folder.appendingPathComponent("\(name).json")))
    expectSame(.object(["result": masked(result), "info": masked(info)]), golden, at: name)

    let codec = PNGJPEGCodec()
    let wrote = try #require(codec.decode(fileAt: out))
    if let dump = ProcessInfo.processInfo.environment["SHOT_CAIRO_GOLDENS"] {
        try FileManager.default.createDirectory(atPath: dump, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: dump + "/command-\(name).png")
        try FileManager.default.copyItem(at: out, to: URL(fileURLWithPath: dump).appendingPathComponent("command-\(name).png"))
    }
    let mac = try #require(codec.decode(fileAt: folder.appendingPathComponent("\(name).png")))
    try #require(mac.width == wrote.width && mac.height == wrote.height)
    var differing = 0, worst = 0
    let a = blocks(of: mac, size: block), b = blocks(of: wrote, size: block)
    for (x, y) in zip(a, b) {
        let most = zip(x, y).map { abs($0 - $1) }.max() ?? 0
        worst = max(worst, most)
        if most > tolerance {
            differing += 1
        }
    }
    let share = Double(differing) / Double(a.count)
    print("\(name): \(differing) of \(a.count) (\(String(format: "%.2f", share * 100))%) differ by more than \(tolerance), the most by \(worst)")
    #expect(share <= maxShare, "\(name): \(String(format: "%.2f", share * 100))% differ by more than \(tolerance)")
    #expect(worst <= maxWorst, "\(name): a channel differs by \(worst)")
}

/// Expects `value` to be `golden`, naming each field that differs by its path, so a failure says which.
private func expectSame(_ value: JSONValue, _ golden: JSONValue, at path: String) {
    switch (value, golden) {
    case let (.object(a), .object(b)):
        #expect(a.keys.sorted() == b.keys.sorted(), "\(path): the fields differ")
        for (key, value) in a {
            if let other = b[key] {
                expectSame(value, other, at: "\(path).\(key)")
            }
        }
    case let (.array(a), .array(b)):
        #expect(a.count == b.count, "\(path): \(a.count) items, where the Mac has \(b.count)")
        for (index, (x, y)) in zip(a, b).enumerated() {
            expectSame(x, y, at: "\(path)[\(index)]")
        }
    default:
        #expect(value == golden, "\(path)")
    }
}

/// `value` without what changes from run to run, or between a Mac and Linux, as CommandGoldenTests masks it.
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

/// Each `size` × `size` block's channels averaged, left to right and top to bottom; a block at the edge is smaller.
private func blocks(of bitmap: Bitmap, size: Int) -> [[Int]] {
    let bytes = [UInt8](bitmap.pixels)
    var result: [[Int]] = []
    for top in stride(from: 0, to: bitmap.height, by: size) {
        for left in stride(from: 0, to: bitmap.width, by: size) {
            var sums = [0, 0, 0, 0], count = 0
            for y in top..<min(top + size, bitmap.height) {
                for x in left..<min(left + size, bitmap.width) {
                    let offset = (y * bitmap.width + x) * 4
                    for channel in 0..<4 {
                        sums[channel] += Int(bytes[offset + channel])
                    }
                    count += 1
                }
            }
            result.append(sums.map { $0 / count })
        }
    }
    return result
}

func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
