import AVFoundation
import CoreGraphics
import Foundation

/// Writes an edit as a new file, so the image editor, the video editor and the `shot` commands name, draw and record
/// a version the same way. The naming itself is `VersionNaming`, in ShotModel.
public enum VersionWriter {
    /// Why an image version couldn't be written.
    public enum Failure: Error {
        /// The document couldn't be drawn.
        case draw
        /// The drawn image couldn't be encoded.
        case encode
        /// The file couldn't be written.
        case write(any Error)
    }

    // MARK: Images

    /// A drawn version: the image, the file's bytes, and the record inside them.
    public struct RenderedImage: @unchecked Sendable {
        public let image: CGImage
        public let file: Data
        public let record: CaptureRecord?
    }

    /// A version written to disk, and its PNG for the clipboard.
    public struct SavedImage: Sendable {
        public let url: URL
        public let png: Data
    }

    /// The next version of `url` for a file written as `format`. It keeps the original's extension when that names
    /// `format`, so "a.jpeg" gives "a (2).jpeg", and otherwise takes the format's own, so "a.heic" saved as PNG gives "a (2).png".
    public static func nextVersionURL(of url: URL, savedAs format: ImageFormat, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let names = format == .png ? ["png"] : ["jpg", "jpeg"]
        let ext = names.contains(url.pathExtension.lowercased()) ? url.pathExtension : format.fileExtension
        return VersionNaming.nextVersionURL(of: url.deletingPathExtension().appendingPathExtension(ext), exists: exists)
    }

    /// What a version records for agents: the marks, in the saved file's pixels, the file they're drawn on, which may
    /// itself be a version, and that file's source, so the version still says which app and window it showed. It's
    /// editable when reopening `original` with the marks gives `document` back. The size is filled in once rendered.
    public static func record(of document: EditorDocument, drawnOn original: URL, savedAs format: ImageFormat, scale: CGFloat) -> CaptureRecord {
        let canvas = document.canvasRect
        // The file is the canvas at 1:1, so the marks need no scaling beyond the canvas offset.
        return CaptureRecord(
            original: original.lastPathComponent, kind: "image", created: Date(), size: CaptureRecord.Size(width: 0, height: 0), scale: scale,
            source: ImageCodec.record(ofFileAt: original)?.source,
            canvas: [canvas.minX, canvas.minY, canvas.width, canvas.height].map { (Double($0) * 10).rounded() / 10 },
            crop: document.visibleCrop.map { [$0.minX, $0.minY, $0.width, $0.height].map { (Double($0) * 10).rounded() / 10 } },
            editable: CaptureMark.rebuildExactly(document.annotations, canvas: canvas) && document.captureStyle.isEmpty && document.captureCornerRadius == 0
                && document.background == EditorDocument.defaultBackground(for: format),
            annotations: CaptureMark.mapping(document.annotations, canvas: canvas)
        )
    }

    /// Flattens `document` and encodes it as `format`, with `record` inside it once it has the drawn size.
    public static func render(_ document: EditorDocument, scale: CGFloat, as format: ImageFormat, record: CaptureRecord?) throws(Failure) -> RenderedImage {
        guard let image = AnnotationRenderer.flatten(document) else {
            throw .draw
        }
        var record = record
        record?.size = CaptureRecord.Size(width: image.width, height: image.height)
        // A window with the macOS shadow still has it once saved, so the file keeps saying so.
        guard let file = ImageCodec.data(from: image, scale: scale, format: format, windowShadow: document.hasWindowShadow, record: record) else {
            throw .encode
        }
        return RenderedImage(image: image, file: file, record: record)
    }

    /// Saves `document`, drawn on the file at `original`, as that file's next version in its own format, as the image
    /// editor's Save does. The version records its marks for agents while `recordForAgents` is on.
    public static func saveImage(_ document: EditorDocument, of original: URL, scale: CGFloat, recordForAgents: Bool = Preferences().agentHandoff) throws(Failure) -> SavedImage {
        let format = ImageFormat(fileExtension: original.pathExtension)
        let record = recordForAgents ? record(of: document, drawnOn: original, savedAs: format, scale: scale) : nil
        let rendered = try render(document, scale: scale, as: format, record: record)
        let png: Data
        if format == .png {
            png = rendered.file
        } else {
            guard let data = ImageCodec.data(from: rendered.image, scale: scale, windowShadow: document.hasWindowShadow, record: rendered.record) else {
                throw .encode
            }
            png = data
        }
        let destination = nextVersionURL(of: original, savedAs: format)
        do {
            try rendered.file.write(to: destination, options: .atomic)
        } catch {
            throw .write(error)
        }
        return SavedImage(url: destination, png: png)
    }

    // MARK: Videos

    /// A new file beside the video at `original` for a copy of an edit of it, named as a new capture is.
    public static func videoCopyURL(of original: URL, prefix: String, date: Date = Date()) -> URL {
        FileNaming.uniqueURL(in: original.deletingLastPathComponent(), date: date, pathExtension: VersionNaming.videoCopyExtension(of: original), prefix: prefix)
    }

    /// How an edit of the video at `original` is written by Save, Save Copy and Copy: in the recording's format when
    /// AVFoundation can write it, and as MP4 otherwise.
    public static func videoPlan(for project: Project, of original: URL) -> VideoExportPlan {
        VideoExportPlan.copy(of: project, as: VersionNaming.videoCopyExtension(of: original) == "mov" ? .mov : .mp4)
    }
}
