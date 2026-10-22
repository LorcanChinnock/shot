import CoreGraphics
import Foundation
// Images reach the on-device model from the macOS 27 SDK (FoundationModels 2.0) on. Built with an older SDK, alt text
// is left out and never shows; CI's scripts/check-sdk.sh fails such a build.
#if canImport(FoundationModels, _version: 2.0)
import FoundationModels
#endif

/// What Shot asks a model about an image: its instructions, the prompt, and how large the image is sent. A type of its
/// own so another model can be asked the same thing later.
public struct ImageRequest: Equatable, Sendable {
    public var instructions: String
    public var prompt: String
    /// The image's longer side is scaled down to this, in pixels, before it's sent.
    public var maxLongEdge: Int

    /// One or two plain sentences that describe a capture for someone who can't see it.
    public static let altText = ImageRequest(
        instructions: """
        You write alt text for screenshots, for people who use a screen reader. Reply with one or two plain sentences: \
        what the screenshot shows, and any text in it that matters. No more than 250 characters. No Markdown, no \
        quotation marks around the reply, and don't start with "Alt text".
        """,
        prompt: "Write alt text for this screenshot.",
        maxLongEdge: 1536
    )
}

/// **Copy Alt Text**: a short description of a capture from Apple's on-device model, which runs on the Mac and needs no
/// key or setup. macOS 27 and later, where the model takes images; it never runs unless asked.
public enum AltText {
    /// Whether the Mac's model is ready and can see images.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels, _version: 2.0)
        guard #available(macOS 27, *) else {
            return false
        }
        let model = SystemLanguageModel.default
        return model.availability == .available && model.capabilities.contains(.vision)
        #else
        return false
        #endif
    }

    public struct Unavailable: LocalizedError {
        public var errorDescription: String? { "This Mac's model can't describe images" }
    }

    /// The alt text for `image`.
    @available(macOS 27, *)
    public static func describe(_ image: CGImage, request: ImageRequest = .altText) async throws -> String {
        #if canImport(FoundationModels, _version: 2.0)
        let scaled = scaled(image, toLongEdge: request.maxLongEdge)
        let session = LanguageModelSession(instructions: request.instructions)
        let response = try await session.respond {
            request.prompt
            Attachment(scaled)
        }
        return cleaned(response.content)
        #else
        throw Unavailable()
        #endif
    }

    /// `image` with its longer side at most `longEdge` pixels; as it is when it's already that small.
    static func scaled(_ image: CGImage, toLongEdge longEdge: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > longEdge, longEdge > 0 else {
            return image
        }
        let factor = Double(longEdge) / Double(long)
        let width = max(1, Int((Double(image.width) * factor).rounded())), height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let context = CGContext.bitmap(width: width, height: height, format: .matching(image)) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// The model's reply as alt text: on one line, without a label or quotes around it, and without Markdown emphasis.
    public static func cleaned(_ reply: String) -> String {
        var text = reply.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        for label in ["Alt text:", "Alt-text:", "Alt Text:", "Description:"] where text.lowercased().hasPrefix(label.lowercased()) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        let quotes: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
        if let first = text.first, let last = text.last, text.count > 1, quotes.contains(where: { $0.0 == first && $0.1 == last }) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
