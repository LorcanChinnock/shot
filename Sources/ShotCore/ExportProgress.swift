import AVFoundation
import Foundation
import Synchronization

/// Splits one export's progress, from 0 to 1, across the steps that make it up.
public enum ExportProgress {
    /// Passes on a step's own progress, from 0 to 1, as the part of the whole from `start` to `end`.
    public static func stage(_ progress: @escaping @Sendable (Double) -> Void, from start: Double, to end: Double) -> @Sendable (Double) -> Void {
        { fraction in
            progress(start + (end - start) * min(max(fraction, 0), 1))
        }
    }

    /// The text to show when an export fails: the error's own description, with AVFoundation's reason after it when it
    /// gives one, since its descriptions alone, such as "Cannot Decode", don't say what went wrong.
    public static func message(for error: any Error) -> String {
        let error = error as NSError
        let description = error.localizedDescription
        guard error.domain == AVFoundationErrorDomain, let reason = error.localizedFailureReason, !reason.isEmpty, reason != description else {
            return description
        }
        return "\(description). \(reason)"
    }

    /// The error's domain and code, and those of the errors under it, for logs: AVFoundation's descriptions are the
    /// same for many failures, and the code beneath tells them apart.
    public static func diagnosis(of error: any Error) -> String {
        var parts: [String] = []
        var next: NSError? = error as NSError
        while let current = next, parts.count < 4 {
            parts.append("\(current.domain) \(current.code)")
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " ← ")
    }
}

/// Turns the frames a GIF asked for into the frames it writes, standing in for any that didn't decode, so one damaged
/// frame doesn't fail the whole export. A frame that fails repeats the last one that decoded, for its own delay; failures
/// before the first good frame add their delays to it, so the GIF still plays for the right length.
struct GIFFrameFill<Image> {
    private var held: Image?
    private var leadingDelay = 0.0
    /// How many frames didn't decode.
    private(set) var skipped = 0
    /// How many frames it has handed on to write.
    private(set) var written = 0
    /// The last decode error, to throw when no frame decoded at all.
    private(set) var lastError: (any Error)?

    /// The picture and delay to write for the next frame, or nil when there's nothing to write yet.
    mutating func next(_ decoded: Result<Image, any Error>, delay: Double) -> (image: Image, delay: Double)? {
        switch decoded {
        case let .success(image):
            held = image
            defer { leadingDelay = 0 }
            written += 1
            return (image, delay + leadingDelay)
        case let .failure(error):
            skipped += 1
            lastError = error
            guard let held else {
                leadingDelay += delay
                return nil
            }
            written += 1
            return (held, delay)
        }
    }
}

extension AVAssetExportSession {
    /// Exports as `export(to:as:)` does, passing on how far it has got, from 0 to 1, a few times a second.
    func export(to url: URL, as fileType: AVFileType, progress: @escaping @Sendable (Double) -> Void) async throws {
        nonisolated(unsafe) let session = self
        let finished = Mutex(false)
        let watcher = Task {
            for await state in session.states(updateInterval: 0.1) {
                guard case let .exporting(current) = state else {
                    continue
                }
                let fraction = current.fractionCompleted
                // Checked under the lock, so a report can't land after the last one.
                finished.withLock { done in
                    if !done { progress(fraction) }
                }
            }
        }
        defer { watcher.cancel() }
        try await export(to: url, as: fileType)
        finished.withLock { $0 = true }
        progress(1)
    }
}
