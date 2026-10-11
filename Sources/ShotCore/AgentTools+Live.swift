import AVFoundation
import Foundation
import ImageIO

extension AgentTools {
    /// The tools reading the captures in `folder`, as the gallery lists them. GIFs count as images: an agent sees their
    /// first frame.
    public static func live(folder: URL) -> AgentTools {
        AgentTools(
            folder: folder,
            entries: {
                Gallery.items(in: folder).map { AgentCaptures.Entry(url: $0.url, isVideo: $0.kind == .video, date: $0.date) }
            },
            preview: { entry in
                entry.isVideo ? await videoPreview(of: entry.url) : imagePreview(of: entry.url)
            },
            record: { entry in
                entry.isVideo ? nil : ImageCodec.record(ofFileAt: entry.url)
            },
            run: { command throws(ShotCommandError) in
                try await ShotCommands.run(command)
            }
        )
    }

    /// A JPEG small enough for a model, and its size beside the file's when they differ, since the marks Shot records
    /// are in the file's pixels.
    static func imagePreview(of url: URL) -> [MCPServer.Content] {
        guard let jpeg = ImageCodec.previewJPEG(at: url) else {
            return [.text("Couldn't read \(url.lastPathComponent) as an image.")]
        }
        var content: [MCPServer.Content] = [.image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg")]
        if let file = pixelSize(of: CGImageSourceCreateWithURL(url as CFURL, nil)),
           let shown = pixelSize(of: CGImageSourceCreateWithData(jpeg as CFData, nil)), file != shown {
            content.append(.text("The preview is \(shown.width)×\(shown.height) pixels. The file is \(file.width)×\(file.height), which is what the marks' coordinates are in."))
        }
        return content
    }

    /// A frame from early on, where a recording has usually settled, plus how long it runs.
    static func videoPreview(of url: URL) async -> [MCPServer.Content] {
        guard let media = try? await MediaProbe.probe(url) else {
            return [.text("Couldn't read \(url.lastPathComponent) as a video.")]
        }
        var content: [MCPServer.Content] = []
        let seconds = min(1, media.duration / 2)
        var about = "A recording \(String(format: "%.1f", media.duration)) seconds long"
        if let size = media.size {
            about += ", \(Int(size.width))×\(Int(size.height))"
        }
        about += media.hasAudio ? ", with sound." : ", without sound."
        if media.size != nil {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1568, height: 1568)
            if let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image,
               let jpeg = ImageCodec.previewJPEG(of: frame) {
                content.append(.image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg"))
                about += " The image is its frame at \(String(format: "%.1f", seconds)) seconds."
            }
        }
        content.append(.text(about))
        return content
    }

    private static func pixelSize(of source: CGImageSource?) -> CaptureRecord.Size? {
        guard let source, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return CaptureRecord.Size(width: width, height: height)
    }
}
