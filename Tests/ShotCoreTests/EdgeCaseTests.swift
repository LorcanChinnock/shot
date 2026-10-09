import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShotCore

// Edge paths in the riskiest ShotCore logic that the behaviour tests beside it don't reach.

private struct DiskFull: Error {}

private func grey(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

// MARK: GIF

@Test func aGIFWriterWhoseOutputFailsThrowsAndCountsNothing() {
    let writer = GIFStreamWriter { _ in throw DiskFull() }
    #expect(throws: DiskFull.self) {
        try writer.add(grey(width: 8, height: 8), delay: 0.1)
    }
    #expect(writer.bytesWritten == 0)
}

@Test func aLaterGIFFrameOfAnotherSizeIsDrawnAtTheFirstFramesSize() throws {
    var data = Data()
    let writer = GIFStreamWriter { data += $0 }
    try writer.add(grey(width: 16, height: 12), delay: 0.1)
    try writer.add(grey(width: 40, height: 6), delay: 0.1)
    try writer.finish()
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetCount(source) == 2)
    let second = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
    #expect(second.width == 16 && second.height == 12)
}

@Test func aOneFrameGIFIsEstimatedAsOneWholeFrame() {
    #expect(GIFExporter.extrapolate(wholeFrameBytes: 900, changeBytes: 50, totalFrames: 1) == 900)
    #expect(GIFExporter.extrapolate(wholeFrameBytes: 900, changeBytes: 50, totalFrames: 0) == 900)
}

@Test func aGIFOfAMissingFileSaysWhy() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    await #expect(throws: (any Error).self) {
        try await GIFExporter.estimatedSize(of: missing, fps: 10, maxWidth: nil)
    }
}

// MARK: Trim and cuts

@Test func aSliverBetweenTwoCutsIsNotKept() {
    // 1 ms is less than a frame at any rate Shot records, and less than `shortestSection`.
    let cuts = CutList([1..<2, 2.001..<3])
    #expect(cuts.cuts.count == 2)
    let range = TrimRange(duration: 10)
    #expect(cuts.kept(in: range) == [TrimRange(start: 0, end: 1, duration: 10), TrimRange(start: 3, end: 10, duration: 10)])
    #expect(abs(cuts.keptLength(in: range) - 8) < 1e-9)
}

@Test func playFromTheEndOfACutStartsThere() {
    let cuts = CutList([2..<3])
    #expect(cuts.playbackStart(from: 3, in: TrimRange(duration: 10)) == 3)
    #expect(cuts.playbackStart(from: 2.5, in: TrimRange(duration: 10)) == 3)
}

// MARK: Keyframes

@Test func settingAKeyframeWithinToleranceReplacesItsValueAndKeepsItsEasing() {
    let keyframes = [Keyframe(time: 1, value: 0.5, easing: .spring)]
    let set = Keyframes.setting(keyframes, at: 1 + Keyframes.tolerance / 2, to: 0.8)
    #expect(set == [Keyframe(time: 1, value: 0.8, easing: .spring)])
}

@Test func removingKeyframesAtATimeLeavesPropertiesWithNoneThere() {
    var animation = ClipAnimation()
    animation.set(.opacity, at: 1, to: PropertyValues(opacity: 0.5))
    animation.set(.scale, at: 1, to: PropertyValues(scale: 2))
    animation.set(.scale, at: 3, to: PropertyValues(scale: 3))
    let removed = animation.removingKeyframes(at: 1)
    #expect(removed.opacity.isEmpty)
    #expect(removed.scale.map(\.time) == [3])
}

@Test func keyframesMovedBeforeTheClipStartLandOnIt() throws {
    let base = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: false)
    let id = base.main.clips[0].id
    let keyed = try #require(base.togglingKeyframe(.opacity, ofClip: id, at: 2))
    let moved = try #require(keyed.movingKeyframes(ofClip: id, from: 2, to: -3))
    #expect(moved.animation(ofClip: id)?.opacity.map(\.time) == [0])
}

// MARK: File naming

@Test func aFileWithNoExtensionGetsANextVersionWithNone() {
    let original = URL(fileURLWithPath: "/tmp/Notes")
    #expect(FileNaming.nextVersionURL(of: original) { _ in false }.lastPathComponent == "Notes (2)")
}

@Test func aFilePrefixCantMakeAHiddenFileOrAPathSeparator() {
    #expect(Preferences.sanitizedPrefix(".hidden") == "hidden")
    #expect(Preferences.sanitizedPrefix("a:b/c") == "a-b-c")
    #expect(Preferences.sanitizedPrefix("...") == Preferences.defaultFilePrefix)
}

// MARK: Preferences

@Test func quickAccessNeverClosingIsKeptAndATileSizeOutOfRangeFallsBack() throws {
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    Preferences.registerDefaults(in: store)
    let prefs = Preferences(store: store)
    store.set(0.0, forKey: PreferenceKey.quickAccessDuration)
    #expect(prefs.quickAccessDuration == 0)
    store.set(1000.0, forKey: PreferenceKey.galleryTileSize)
    #expect(prefs.galleryTileSize == Gallery.defaultTileSize)
    store.set(200.0, forKey: PreferenceKey.galleryTileSize)
    #expect(prefs.galleryTileSize == 200)
}
