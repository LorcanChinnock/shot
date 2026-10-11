import AppKit
import ShotCore
import UniformTypeIdentifiers

struct SendableImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

@MainActor
enum Clipboard {
    /// PNG only: apps read it, and a TIFF beside it cost about 15 ms and a screen-sized buffer per capture (#276).
    static func copy(png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pasteboard.writeObjects([item])
    }

    /// The PNG and, for agents, `path` as plain text on one item: a terminal pastes the path, and an app that reads
    /// images pastes the image. The PNG goes first, so apps that take the first type they know take the image.
    static func copy(png: Data, path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(path, forType: .string)
        pasteboard.writeObjects([item])
    }

    /// Copies the image as PNG, which is the file's own bytes when it is one, with `path` beside it as `copy(png:path:)`
    /// does when given; false if it can't be read.
    static func copy(imageAt url: URL, path: String? = nil) -> Bool {
        guard let image = ImageCodec.image(at: url) else {
            return false
        }
        let png = ImageFormat(fileExtension: url.pathExtension) == .png ? try? Data(contentsOf: url) : nil
        guard let data = png ?? ImageCodec.data(from: image, scale: ImageCodec.scale(ofFileAt: url)) else {
            return false
        }
        if let path {
            copy(png: data, path: path)
        } else {
            copy(png: data)
        }
        return true
    }

    static func copy(string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    static func copy(fileURL: URL) {
        copy(fileURLs: [fileURL])
    }

    /// The file and, for agents, `path` as plain text on one item. The file URL type is what an `NSURL` writes, and Finder's
    /// own copies carry the same pair, so apps that paste files are unaffected.
    static func copy(fileURL: URL, path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(path, forType: .string)
        pasteboard.writeObjects([item])
    }

    static func copy(fileURLs: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    private static let annotationType = NSPasteboard.PasteboardType(AnnotationClipboard.pasteboardType)

    /// Encodes off the main actor, since a placed image is encoded as PNG.
    static func copy(annotation: Annotation) async throws {
        let data = try await Task.detached { try AnnotationClipboard.data(for: annotation) }.value
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: annotationType)
    }

    /// The annotation on the pasteboard, or `nil` if it holds something else.
    static func annotation() throws -> Annotation? {
        guard let data = NSPasteboard.general.data(forType: annotationType) else {
            return nil
        }
        return try AnnotationClipboard.annotation(from: data)
    }

    private static let imageFiles: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// Whether `pasteboard` holds an image `images(on:)` can read, without reading it.
    static func hasImages(on pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFiles)
        }
        return imageType(on: pasteboard) != nil
    }

    /// The images on `pasteboard`, encoded: the contents of each image file, else its PNG, else its
    /// first image type. Files that aren't images give nothing, rather than the icon Finder copies with them.
    static func images(on pasteboard: NSPasteboard) -> [Data] {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFiles) as? [URL] ?? []
            return urls.compactMap { url in
                do {
                    return try Data(contentsOf: url)
                } catch {
                    Toast.error("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
        }
        return imageType(on: pasteboard).flatMap { pasteboard.data(forType: $0) }.map { [$0] } ?? []
    }

    /// PNG if it's there, since it keeps the scale, else the first type that's an image.
    private static func imageType(on pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType? {
        let types = pasteboard.types ?? []
        if types.contains(.png) {
            return .png
        }
        return types.first { UTType($0.rawValue)?.conforms(to: .image) == true }
    }
}

@MainActor
enum Sound {
    private static let shutter = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif", byReference: true)

    static func capture() {
        shutter?.stop()
        shutter?.play()
    }
}
