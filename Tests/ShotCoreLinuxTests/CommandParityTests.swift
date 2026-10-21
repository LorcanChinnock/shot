import Foundation
import Testing
@testable import ShotCoreLinux

// Each case in Tests/Fixtures/commands/cases.json run on Linux, through PNGJPEGCodec, CairoCanvas and ffmpeg, and
// compared with what ShotCoreAppleTests' CommandGoldenTests wrote on a Mac: the JSON it and `info` on its output print,
// field by field with paths, sizes in bytes, dates and IDs masked and times within a frame or two, and what it wrote,
// within each case's limits as CairoGoldenTests compares the canvas goldens. A video or GIF is compared by its frames
// a fifth, a half and four fifths of the way through, as ffmpeg reads both, and a folder of frames picture by picture.
// Set SHOT_CAIRO_GOLDENS to a folder to write what Linux wrote there, to look at.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/commands")
private let canvas = folder.deletingLastPathComponent().appendingPathComponent("canvas")

private struct Case: Codable, Sendable {
    var name: String
    var args: [String]
    /// What the command writes: `png`, the default, `gif`, `mp4`, `folder`, or `none`.
    var out: String?
}

/// How far a time or duration may be from the Mac's, in seconds, three frames at 30 fps: AVFoundation and ffmpeg cut at
/// frames a little apart, and a copied section's length counts from the sync frame ffmpeg seeks to.
private let timeTolerance = 0.1

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

/// The cases that read video, compared in 4-pixel blocks, since each encoder blurs edges its own way and a frame read a
/// frame apart is 4 gray levels off.
private let videoLimits: [(name: String, block: Int, share: Double, worst: Int)] = [
    ("infoVideo", 4, 0, 0),
    ("gif", 4, 0, 16),
    ("trim", 4, 0, 16),
    ("editVideo", 4, 0.02, 48),
    ("speed", 4, 0, 16),
    // An arrow's antialiased edge, 80 pixels wide in each GIF's own palette, over a gray AVFoundation decodes a dozen
    // levels brighter than ffmpeg does.
    ("editGIF", 4, 0.1, 64),
    ("frames", 4, 0, 16),
]

@Test func everyCommandCaseHasLimits() throws {
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
    #expect(cases.map(\.name) == (limits + videoLimits).map(\.name))
}

@Test(arguments: limits)
func theCommandWritesAndPrintsWhatItDoesOnAMac(name: String, block: Int, share maxShare: Double, worst maxWorst: Int) async throws {
    let (work, out, _) = try await run(name)
    defer { try? FileManager.default.removeItem(at: work) }
    let codec = PNGJPEGCodec()
    let wrote = try #require(codec.decode(fileAt: out))
    let mac = try #require(codec.decode(fileAt: folder.appendingPathComponent("\(name).png")))
    expectNear(wrote, mac, name: name, block: block, share: maxShare, worst: maxWorst)
}

@Test(.enabled(if: hasFFmpeg, "ffmpeg isn't installed"), .serialized, arguments: videoLimits)
func theVideoCommandWritesAndPrintsWhatItDoesOnAMac(name: String, block: Int, share maxShare: Double, worst maxWorst: Int) async throws {
    let (work, out, kind) = try await run(name)
    defer { try? FileManager.default.removeItem(at: work) }
    let golden = folder.appendingPathComponent(out.lastPathComponent)
    switch kind {
    case "gif", "mp4":
        let duration = min(try await probe(out).duration, try await probe(golden).duration)
        let times = [0.2, 0.5, 0.8].map { $0 * duration }
        let wrote = try await frames(of: out, at: times), mac = try await frames(of: golden, at: times)
        try #require(wrote.count == times.count && mac.count == times.count)
        for (index, (a, b)) in zip(wrote, mac).enumerated() {
            let image = try a.decoded.get().image, macImage = try b.decoded.get().image
            expectNear(image.bitmap, macImage.bitmap, name: "\(name) at \(String(format: "%.2f", times[index])) s", block: block, share: maxShare, worst: maxWorst)
        }
    case "folder":
        let codec = PNGJPEGCodec()
        let names = try FileManager.default.contentsOfDirectory(atPath: golden.path).sorted()
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).sorted() == names)
        for file in names {
            let wrote = try #require(codec.decode(fileAt: out.appendingPathComponent(file)))
            let mac = try #require(codec.decode(fileAt: golden.appendingPathComponent(file)))
            expectNear(wrote, mac, name: "\(name)/\(file)", block: block, share: maxShare, worst: maxWorst)
        }
    default:
        break
    }
}

/// Runs the case `name` in a new folder holding the canvas goldens' images and the video fixtures' `timed.mp4`, expects
/// it and `info` on what it wrote to print what they did on a Mac, and gives the folder, what it wrote, and the case's
/// `out`.
private func run(_ name: String) async throws -> (work: URL, out: URL, kind: String) {
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
    let test = try #require(cases.first { $0.name == name })
    let work = try temporaryFolder()
    for file in ["base.png", "lines.png"] {
        try FileManager.default.copyItem(at: canvas.appendingPathComponent(file), to: work.appendingPathComponent(file))
    }
    try FileManager.default.copyItem(at: timed, to: work.appendingPathComponent("timed.mp4"))
    let kind = test.out ?? "png"
    let out = work.appendingPathComponent(kind == "folder" || kind == "none" ? name : "\(name).\(kind)")
    let args = test.args.map {
        $0.replacingOccurrences(of: "{base}", with: work.appendingPathComponent("base.png").path)
            .replacingOccurrences(of: "{lines}", with: work.appendingPathComponent("lines.png").path)
            .replacingOccurrences(of: "{timed}", with: work.appendingPathComponent("timed.mp4").path)
            .replacingOccurrences(of: "{fixtures}", with: folder.path)
            .replacingOccurrences(of: "{out}", with: out.path)
    }
    let result = try await ShotCommands.run(try ShotCommand.parse(args))
    var printed: [String: JSONValue] = ["result": masked(result)]
    if !["none", "folder"].contains(kind) {
        printed["info"] = masked(try await ShotCommands.run(.info(path: out.path)))
    }
    let golden = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: folder.appendingPathComponent("\(name).json")))
    expectSame(.object(printed), golden, at: name)
    if let dump = ProcessInfo.processInfo.environment["SHOT_CAIRO_GOLDENS"], kind != "none" {
        try FileManager.default.createDirectory(atPath: dump, withIntermediateDirectories: true)
        let copy = URL(fileURLWithPath: dump).appendingPathComponent("command-\(out.lastPathComponent)")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: out, to: copy)
    }
    return (work, out, kind)
}

/// Expects `wrote` to be the size of `mac`, with no more than `share` of its `block` × `block` blocks differing by more
/// than `tolerance` and none by more than `worst`.
private func expectNear(_ wrote: Bitmap, _ mac: Bitmap, name: String, block: Int, share maxShare: Double, worst maxWorst: Int) {
    guard mac.width == wrote.width && mac.height == wrote.height else {
        Issue.record("\(name): \(wrote.width) × \(wrote.height), where the Mac's is \(mac.width) × \(mac.height)")
        return
    }
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
    case let (.number(a), .number(b)) where path.hasSuffix(".duration") || path.hasSuffix(".time"):
        #expect(abs(a - b) <= timeTolerance, "\(path): \(a), where the Mac has \(b)")
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
