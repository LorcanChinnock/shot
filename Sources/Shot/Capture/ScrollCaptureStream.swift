import AppKit
import CoreMedia
import os
import ScreenCaptureKit
import ShotCore

/// What `ScrollStitchWorker` reports after each frame.
struct ScrollUpdate: @unchecked Sendable {
    /// `nil` for the first frame, which only starts the image.
    var outcome: ScrollStitcher.Outcome?
    /// The size of the whole image in pixels.
    var size: CGSize
    /// The whole image shrunk down, and where the newest frame sits in it as a share of its width and height, when the
    /// image changed and the last overview is old enough to replace.
    var preview: CGImage?
    var view = CGRect.zero
}

/// Runs the stitcher off the main actor, one frame at a time.
actor ScrollStitchWorker {
    private var stitcher: ScrollStitcher?
    private var lastPreview = ContinuousClock.now - .seconds(1)
    /// The size the overview is shrunk to fit, in pixels: the panel's preview box at twice its size.
    static let previewBox = (width: 520, height: 260)

    func add(_ frame: Bitmap) -> ScrollUpdate {
        guard stitcher != nil else {
            stitcher = ScrollStitcher(first: frame)
            return update(outcome: nil, changed: true)
        }
        let outcome = stitcher!.add(frame)
        return update(outcome: outcome, changed: outcome == .extended || outcome == .limit)
    }

    func result() -> Bitmap? {
        stitcher?.finish()
        return stitcher?.result
    }

    private func update(outcome: ScrollStitcher.Outcome?, changed: Bool) -> ScrollUpdate {
        guard let stitcher else {
            return ScrollUpdate(outcome: outcome, size: .zero, preview: nil, view: .zero)
        }
        let now = ContinuousClock.now
        // Shrinking the image costs a little, so the overview refreshes a few times a second.
        var preview: CGImage?
        var view = CGRect.zero
        if changed, now - lastPreview > .milliseconds(250) {
            let overview = stitcher.overview(fitting: Self.previewBox)
            preview = overview.image.cgImage
            view = overview.view
            lastPreview = now
        }
        let size = stitcher.size
        return ScrollUpdate(outcome: outcome, size: CGSize(width: size.width, height: size.height), preview: preview, view: view)
    }
}

/// Receives the area's frames from ScreenCaptureKit and hands them to `handler`, dropping any that arrive while the
/// last is still being stitched, so a slow match never builds a backlog.
final class ScrollFrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "Shot.scrollframes")
    private let busy = OSAllocatedUnfairLock(initialState: false)
    private let scale: CGFloat
    private let handler: @Sendable (Bitmap) async -> Void

    init(scale: CGFloat, handler: @escaping @Sendable (Bitmap) async -> Void) {
        self.scale = scale
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = sampleBuffer.imageBuffer else {
            return
        }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        guard let raw = attachments?.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else {
            return
        }
        let free = busy.withLock { busy -> Bool in
            if busy {
                return false
            }
            busy = true
            return true
        }
        guard free else {
            return
        }
        guard let bitmap = Self.bitmap(from: buffer, scale: scale) else {
            busy.withLock { $0 = false }
            return
        }
        Task {
            await handler(bitmap)
            busy.withLock { $0 = false }
        }
    }

    private static func bitmap(from buffer: CVPixelBuffer, scale: CGFloat) -> Bitmap? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ),
              let image = context.makeImage()
        else {
            return nil
        }
        return Bitmap(image, scale: scale)
    }
}
