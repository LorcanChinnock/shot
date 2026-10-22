import CoreGraphics
import Foundation

/// The services Settings lists for the OpenAI-compatible request format, local ones first.
public enum ProviderPreset: String, CaseIterable, Sendable {
    case ollama, lmStudio, openAI, gemini, openRouter, custom

    public var name: String {
        switch self {
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    /// Where requests go; empty for Custom, which the user fills in.
    public var baseURL: String {
        switch self {
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }

    /// A model that sees images, as a starting point; empty when it depends on what's installed.
    public var suggestedModel: String {
        switch self {
        case .ollama: "qwen2.5vl"
        case .lmStudio: ""
        case .openAI: "gpt-4o-mini"
        case .gemini: "gemini-2.0-flash"
        case .openRouter: "openai/gpt-4o-mini"
        case .custom: ""
        }
    }

    /// Whether the service runs on the Mac, so a capture never leaves it.
    public var isLocal: Bool { self == .ollama || self == .lmStudio }
}

/// An image as the provider receives it: encoded, and small enough.
public struct ProviderImage: Equatable, Sendable {
    public var data: Data
    public var mimeType: String

    public static let maximumLongEdge = 2000
    public static let maximumBytes = 5_000_000
    public static let maximumPerRequest = 20

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }

    /// `image` as a JPEG with its longer side at most 2000 px and under 5 MB, or `nil` when it can't be made that small.
    public static func encoding(_ image: CGImage) -> ProviderImage? {
        guard let data = ImageCodec.previewJPEG(of: image, maxPixelSize: maximumLongEdge, maxBytes: maximumBytes - 1), data.count < maximumBytes else {
            return nil
        }
        return ProviderImage(data: data, mimeType: "image/jpeg")
    }

    /// The `data:` URL base64 form, since Ollama's compatible endpoint takes no web URLs.
    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// An OpenAI-compatible chat completions endpoint: one request format for OpenAI, Gemini's compatible endpoint,
/// OpenRouter, and local Ollama or LM Studio. Only runs when an action asks for it.
public struct ChatProvider: Sendable {
    public var baseURL: String
    public var model: String
    /// From the Keychain; local services take none.
    public var apiKey: String

    public init(baseURL: String, model: String, apiKey: String = "") {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    public enum Failure: LocalizedError, Equatable {
        case notSet
        case badURL
        case tooManyImages
        case server(status: Int, message: String?)
        case malformed(String)
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .notSet: "Choose a provider and model in Settings first"
            case .badURL: "The provider's address isn't valid"
            case .tooManyImages: "A request takes at most \(ProviderImage.maximumPerRequest) images"
            case .server(let status, let message): message.map { "The provider said: \($0)" } ?? "The provider answered with status \(status)"
            case .malformed(let reason): "The provider's reply wasn't usable: \(reason)"
            case .refused(let reason): "The provider declined: \(reason)"
            }
        }
    }

    /// The `chat/completions` URL under the base URL.
    public func endpoint() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard !base.isEmpty, let url = URL(string: base + "/chat/completions"), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            throw Failure.badURL
        }
        return url
    }

    /// The request for `request` with `images`, asking for a reply that fits `schema` (strict structured output).
    public func urlRequest(for request: ImageRequest, images: [ProviderImage], schema: JSONValue, schemaName: String = "reply") throws -> URLRequest {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Failure.notSet
        }
        guard images.count <= ProviderImage.maximumPerRequest else {
            throw Failure.tooManyImages
        }
        if let problem = ProviderSchema.problem(with: schema) {
            throw Failure.malformed(problem)
        }
        var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(request.prompt)])]
        for image in images {
            content.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string(image.dataURL)])]))
        }
        let body: JSONValue = .object([
            "model": .string(model),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(request.instructions)]),
                .object(["role": .string("user"), "content": .array(content)]),
            ]),
            "response_format": .object([
                "type": .string("json_schema"),
                "json_schema": .object(["name": .string(schemaName), "strict": .bool(true), "schema": schema]),
            ]),
        ])
        var urlRequest = URLRequest(url: try endpoint())
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    /// The reply in `data`, an HTTP `status` response, checked against `schema`.
    public static func parse(_ data: Data, status: Int, schema: JSONValue) throws -> JSONValue {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.string
            throw Failure.server(status: status, message: message)
        }
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .array(let choices)? = root["choices"], let choice = choices.first else {
            throw Failure.malformed("no choices")
        }
        if let refusal = choice["message"]?["refusal"]?.string, !refusal.isEmpty {
            throw Failure.refused(refusal)
        }
        guard let text = choice["message"]?["content"]?.string, !text.isEmpty else {
            throw Failure.malformed("no content")
        }
        guard let reply = try? JSONDecoder().decode(JSONValue.self, from: Data(unwrapped(text).utf8)) else {
            throw Failure.malformed("the content isn't JSON")
        }
        if let problem = ProviderSchema.problem(with: reply, against: schema) {
            throw Failure.malformed(problem)
        }
        return reply
    }

    /// `text` without a Markdown code fence around it, which local models sometimes add despite the schema.
    static func unwrapped(_ text: String) -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2, lines.first?.hasPrefix("```") == true, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
            return text
        }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    /// Sends `request` and returns the reply, which fits `schema`.
    public func send(_ request: ImageRequest, images: [ProviderImage], schema: JSONValue, session: URLSession = .shared) async throws -> JSONValue {
        let (data, response) = try await session.data(for: urlRequest(for: request, images: images, schema: schema))
        return try Self.parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0, schema: schema)
    }

    /// Alt text for `image`. The reply is an object with one `text` field.
    public func altText(for image: CGImage, request: ImageRequest = .altText, session: URLSession = .shared) async throws -> String {
        guard let encoded = ProviderImage.encoding(image) else {
            throw Failure.malformed("the image couldn't be prepared")
        }
        let reply = try await send(request, images: [encoded], schema: Self.textSchema, session: session)
        return AltText.cleaned(reply["text"]?.string ?? "")
    }

    static let textSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(["text": .object(["type": .string("string")])]),
        "required": .array([.string("text")]),
        "additionalProperties": .bool(false),
    ])
}
