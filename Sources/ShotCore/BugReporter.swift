import CoreGraphics
import Foundation
#if canImport(FoundationModels, _version: 2.0)
import FoundationModels
#endif

/// **Copy Bug Report**, end to end: reads a capture or recording, asks a model, and returns Markdown. Only runs when an
/// action asks for it; the text and speech are read on the Mac, and only the frames and what was read go to a provider
/// the user set up.
public enum BugReporter {
    public struct Gathered: @unchecked Sendable {
        public var input: BugReport.Input
        public var images: [CGImage]
    }

    /// The frames, text and transcript of the image or recording at `url`, at most `frames` frames.
    public static func gather(from url: URL, frames count: Int) async throws -> Gathered {
        let record = ImageCodec.record(ofFileAt: url)
        let notes = record?.annotations.filter { $0.type == "note" }.compactMap(\.text) ?? []
        if let image = ImageCodec.image(at: url) {
            return await gather(from: image, record: record)
        }
        guard let media = try? await MediaProbe.probe(url), media.size != nil else {
            throw Unreadable()
        }
        async let heard = AgentTools.narration(of: url, hasAudio: media.hasAudio)
        let times = try await KeyFrameExtractor.changeTimes(in: url, duration: media.duration, count: count)
        let stills = try await KeyFrameExtractor.frames(of: url, at: times, maxWidth: 1024)
        let said = Narration.align(await heard.phrases, to: stills.map(\.time))
        var frames: [BugReport.Frame] = []
        for (index, still) in stills.enumerated() {
            let text = try? await TextRecognizer.recognize(still.image)
            frames.append(BugReport.Frame(time: still.time, text: text?.lines.map(\.text) ?? [], said: said[index]))
        }
        return Gathered(input: BugReport.Input(app: record?.source?.app, windowTitle: record?.source?.windowTitle, duration: media.duration, notes: notes, frames: frames), images: stills.map(\.image))
    }

    /// A single image, such as the editor's current picture with its marks.
    public static func gather(from image: CGImage, record: CaptureRecord?) async -> Gathered {
        let notes = record?.annotations.filter { $0.type == "note" }.compactMap(\.text) ?? []
        let text = try? await TextRecognizer.recognize(image)
        let lines = text?.lines.map(\.text) ?? []
        return Gathered(input: BugReport.Input(app: record?.source?.app, windowTitle: record?.source?.windowTitle, notes: notes, frames: [BugReport.Frame(text: lines)]), images: [image])
    }

    public struct Unreadable: LocalizedError {
        public init() {}
        public var errorDescription: String? { "Couldn't read this file as an image or video" }
    }

    /// Whether Apple's on-device model can write one: it has to see images.
    public static var onDeviceAvailable: Bool { AltText.isAvailable }

    /// The Markdown bug report for the image or recording at `url`, from `provider` or, with none, the Mac's model.
    public static func report(for url: URL, provider: ChatProvider?) async throws -> String {
        let budget: BugReport.Budget = provider == nil ? .onDevice : .provider
        return try await report(gathering: { try await gather(from: url, frames: budget.frames) }, provider: provider)
    }

    /// The Markdown bug report for `image`.
    public static func report(for image: CGImage, provider: ChatProvider?) async throws -> String {
        try await report(gathering: { await gather(from: image, record: nil) }, provider: provider)
    }

    private static func report(gathering: () async throws -> Gathered, provider: ChatProvider?) async throws -> String {
        var budget: BugReport.Budget = provider == nil ? .onDevice : .provider
        let gathered = try await gathering()
        while true {
            do {
                return try await report(gathered, budget: budget, provider: provider)
            } catch let failure as ChatProvider.Failure where failure.isContextTooSmall && budget.frames > 1 {
                // A local model often runs with a small context (Ollama starts at 4,096 tokens), so try again with
                // fewer frames rather than fail on a long recording.
                budget.frames /= 2
            } catch let failure as ChatProvider.Failure where failure.isContextTooSmall {
                throw ChatProvider.Failure.malformed("the model's context is too small for this capture. Raise the context length in the model's settings, or choose a model with more")
            }
        }
    }

    private static func report(_ gathered: Gathered, budget: BugReport.Budget, provider: ChatProvider?) async throws -> String {
        let prepared = BugReport.prepare(gathered.input, budget: budget)
        let images = prepared.frames.map { gathered.images[$0] }
        let reply: JSONValue
        if let provider {
            let encoded = try images.map { image in
                guard let encoded = ProviderImage.encoding(image) else { throw ChatProvider.Failure.malformed("the image couldn't be prepared") }
                return encoded
            }
            reply = try await provider.send(prepared.request, images: encoded, schema: BugReport.schema)
        } else {
            reply = try await onDeviceReply(prepared.request, images: images)
        }
        var markdown = BugReport.markdown(from: reply, readText: prepared.text)
        if prepared.trimmed {
            markdown += "\n_Written from part of the capture: some frames and text were left out to fit._\n"
        }
        return markdown
    }

    #if canImport(FoundationModels, _version: 2.0)
    @available(macOS 27, *)
    @Generable
    struct Reply {
        @Guide(description: "A short title naming the problem") var title: String
        @Guide(description: "What the user did, one short action per item") var steps: [String]
        @Guide(description: "What should have happened") var expected: String
        @Guide(description: "What happened instead") var actual: String
        @Guide(description: "Error messages exactly as in the text read from the images; empty if none") var errors: [String]
    }
    #endif

    private static func onDeviceReply(_ request: ImageRequest, images: [CGImage]) async throws -> JSONValue {
        #if canImport(FoundationModels, _version: 2.0)
        guard #available(macOS 27, *) else { throw AltText.Unavailable() }
        let session = LanguageModelSession(instructions: request.instructions)
        let scaled = images.map { AltText.scaled($0, toLongEdge: request.maxLongEdge) }
        let response = try await session.respond(generating: Reply.self) {
            request.prompt
            for image in scaled { Attachment(image) }
        }
        let reply = response.content
        return .object([
            "title": .string(reply.title),
            "steps": .array(reply.steps.map(JSONValue.string)),
            "expected": .string(reply.expected),
            "actual": .string(reply.actual),
            "errors": .array(reply.errors.map(JSONValue.string)),
        ])
        #else
        throw AltText.Unavailable()
        #endif
    }
}
