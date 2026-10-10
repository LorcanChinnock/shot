import AVFoundation
import ImageIO
import os
import Testing
@testable import ShotCore

extension MediaTests {
    @Test func exportsTwoSecondVideoAtTwelveFPS() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        let gif = folder.appendingPathComponent("out.gif")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 1280, height: 720)

        let result = try await GIFExporter.export(videoURL: video, to: gif)

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        let frames = CGImageSourceGetCount(source)
        #expect(abs(frames - 24) <= 1)
        #expect(result.frameCount == frames)
        #expect(!result.truncated)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 720)
        #expect(first.height == 405)

        let file = try #require(ParsedGIF(try Data(contentsOf: gif)))
        #expect(file.signature == "GIF89a")
        #expect(file.width == 720 && file.height == 405)
        #expect(file.loopCount == 0)
        #expect(file.frames.count == result.frameCount)
        let plan = GIFFramePlan(sourceSize: CGSize(width: 1280, height: 720), range: TrimRange(duration: 2), fps: 12, maxWidth: 720)
        #expect(file.frames.map(\.delay) == (0..<result.frameCount).map { Int((plan.delay(ofFrame: $0) * 100).rounded()) })
    }

    @Test func aGIFOfARecordingWithNoPictureSaysWhy() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sound = folder.appendingPathComponent("sound.mp4")
        let gif = folder.appendingPathComponent("out.gif")
        try await writeScreenRecording(to: sound, seconds: 1, audio: true, video: false)

        await #expect(throws: GIFExporter.ExportError.noVideoTrack) { try await GIFExporter.export(videoURL: sound, to: gif) }
        await #expect(throws: GIFExporter.ExportError.noVideoTrack) { try await GIFExporter.estimatedSize(of: sound, fps: 10, maxWidth: nil) }
        #expect(!FileManager.default.fileExists(atPath: gif.path))
    }

    @Test func aGIFThatCantBeCreatedSaysWhy() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        try await writeSyntheticVideo(to: video, seconds: 1, fps: 30, width: 320, height: 240)

        await #expect(throws: GIFExporter.ExportError.cannotCreateDestination) {
            try await GIFExporter.export(videoURL: video, to: folder.appendingPathComponent("missing/out.gif"))
        }
    }

    @Test func cancellingAGIFExportStopsBeforeTheNextFrameAndLeavesNoFile() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        let gif = folder.appendingPathComponent("out.gif")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 320, height: 240)
        let framesWritten = OSAllocatedUnfairLock(initialState: 0)

        let export = Task {
            try await GIFExporter.export(videoURL: video, to: gif) { _ in
                framesWritten.withLock { $0 += 1 }
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }

        await #expect(throws: CancellationError.self) { try await export.value }
        #expect(framesWritten.withLock { $0 } == 1)
        #expect(!FileManager.default.fileExists(atPath: gif.path))
    }
}

// MARK: Streaming writer

/// A GIF's blocks, read without ImageIO.
struct ParsedGIF {
    struct Frame {
        var x, y, width, height: Int
        var delay: Int
        var hasLocalColorTable: Bool
    }

    var signature: String
    var width, height: Int
    var loopCount: Int?
    var frames: [Frame] = []

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        func word(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func skipSubBlocks(_ at: Int) -> Int {
            var index = at
            while bytes[index] != 0 { index += Int(bytes[index]) + 1 }
            return index + 1
        }
        guard bytes.count > 13 else { return nil }
        signature = String(decoding: bytes[0..<6], as: UTF8.self)
        width = word(6)
        height = word(8)
        var index = 13 + (bytes[10] & 0x80 != 0 ? 3 << (Int(bytes[10] & 7) + 1) : 0)
        var delay = 0
        while index < bytes.count {
            switch bytes[index] {
            case 0x21 where bytes[index + 1] == 0xF9:
                delay = word(index + 4)
                index = skipSubBlocks(index + 2)
            case 0x21 where bytes[index + 1] == 0xFF:
                if String(decoding: bytes[index + 3..<index + 14], as: UTF8.self) == "NETSCAPE2.0" { loopCount = word(index + 16) }
                index = skipSubBlocks(index + 2)
            case 0x21:
                index = skipSubBlocks(index + 2)
            case 0x2C:
                let packed = bytes[index + 9]
                frames.append(Frame(x: word(index + 1), y: word(index + 3), width: word(index + 5), height: word(index + 7), delay: delay, hasLocalColorTable: packed & 0x80 != 0))
                index = skipSubBlocks(index + 10 + (packed & 0x80 != 0 ? 3 << (Int(packed & 7) + 1) : 0) + 1)
            case 0x3B:
                return
            default:
                return nil
            }
        }
        return nil
    }
}

private func solidImage(width: Int, height: Int, background: CGColor, box: CGRect? = nil) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let box {
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(box)
    }
    return context.makeImage()!
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var rgba = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    return rgba
}

@Test func streamedGIFStoresOnlyWhatChangedAndStillPlaysEveryFrame() throws {
    let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    // Core Graphics counts up from the bottom; the box is 8 px from the top and 4 from the left.
    let frames = [
        solidImage(width: 64, height: 48, background: blue),
        solidImage(width: 64, height: 48, background: blue, box: CGRect(x: 4, y: 30, width: 10, height: 10)),
        solidImage(width: 64, height: 48, background: blue, box: CGRect(x: 4, y: 30, width: 10, height: 10)),
    ]
    var data = Data()
    let writer = GIFStreamWriter { data += $0 }
    for (frame, delay) in zip(frames, [0.07, 0.06, 0.5]) {
        try writer.add(frame, delay: delay)
    }
    try writer.finish()
    #expect(writer.bytesWritten == data.count)

    let file = try #require(ParsedGIF(data))
    #expect(file.signature == "GIF89a")
    #expect(file.width == 64 && file.height == 48)
    #expect(file.loopCount == 0)
    #expect(file.frames.map(\.delay) == [7, 6, 50])
    #expect(file.frames.allSatisfy { $0.hasLocalColorTable })
    #expect(file.frames.map { [$0.x, $0.y, $0.width, $0.height] } == [[0, 0, 64, 48], [4, 8, 10, 10], [0, 0, 1, 1]])

    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetCount(source) == 3)
    for index in 0..<3 {
        let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
        #expect(pixel(image, x: 0, y: 0) == [0, 0, 255, 255], "frame \(index)")
        #expect(pixel(image, x: 8, y: 12) == (index == 0 ? [0, 0, 255, 255] : [255, 0, 0, 255]), "frame \(index)")
    }
}
