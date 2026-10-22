import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func object(_ properties: [String: JSONValue]) -> JSONValue {
    .object(["type": .string("object"), "properties": .object(properties), "required": .array(properties.keys.sorted().map { .string($0) }), "additionalProperties": .bool(false)])
}

private let text: JSONValue = .object(["type": .string("string")])

private func reply(_ content: String) -> Data {
    let body: JSONValue = .object(["choices": .array([.object(["message": .object(["content": .string(content)])])])])
    return try! JSONEncoder().encode(body)
}

@Test func theStrictSubsetIsAccepted() {
    let schema = object([
        "title": text,
        "count": .object(["type": .string("integer")]),
        "note": .object(["type": .array([.string("string"), .string("null")])]),
        "kind": .object(["type": .string("string"), "enum": .array([.string("a"), .string("b")])]),
        "steps": .object(["type": .string("array"), "items": object(["line": text])]),
    ])
    #expect(ProviderSchema.problem(with: schema) == nil)
}

@Test func schemasOutsideTheSubsetAreRejected() {
    #expect(ProviderSchema.problem(with: text) != nil)
    #expect(ProviderSchema.problem(with: object(["a": .object(["oneOf": .array([text])])]))?.contains("oneOf") == true)
    #expect(ProviderSchema.problem(with: object(["a": .object(["type": .string("string"), "pattern": .string("x")])]))?.contains("pattern") == true)
    var loose = object(["a": text])
    if case .object(var fields) = loose {
        fields["additionalProperties"] = .bool(true)
        loose = .object(fields)
    }
    #expect(ProviderSchema.problem(with: loose)?.contains("additionalProperties") == true)
    var optional = object(["a": text, "b": text])
    if case .object(var fields) = optional {
        fields["required"] = .array([.string("a")])
        optional = .object(fields)
    }
    #expect(ProviderSchema.problem(with: optional)?.contains("required") == true)
    #expect(ProviderSchema.problem(with: object(["a": .object(["type": .string("array"), "items": object(["b": object(["c": object(["d": text])])])])]))?.contains("nested") == true)
}

@Test func repliesAreCheckedAgainstTheSchema() {
    let schema = object(["text": text, "note": .object(["type": .array([.string("string"), .string("null")])])])
    #expect(ProviderSchema.problem(with: .object(["text": .string("hi"), "note": .null]), against: schema) == nil)
    #expect(ProviderSchema.problem(with: .object(["text": .string("hi")]), against: schema)?.contains("missing note") == true)
    #expect(ProviderSchema.problem(with: .object(["text": .number(1), "note": .null]), against: schema) != nil)
    #expect(ProviderSchema.problem(with: .object(["text": .string("hi"), "note": .null, "extra": .null]), against: schema)?.contains("extra") == true)
    let kind = object(["kind": .object(["type": .string("string"), "enum": .array([.string("a")])])])
    #expect(ProviderSchema.problem(with: .object(["kind": .string("b")]), against: kind) != nil)
}

@Test func theRequestCarriesTheImageAndAStrictSchema() throws {
    let provider = ChatProvider(baseURL: "http://localhost:11434/v1/", model: "qwen2.5vl", apiKey: "")
    let image = ProviderImage(data: Data([1, 2, 3]), mimeType: "image/jpeg")
    let request = try provider.urlRequest(for: .altText, images: [image], schema: ChatProvider.textSchema)
    #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
    #expect(body["model"] == .string("qwen2.5vl"))
    #expect(body["response_format"]?["json_schema"]?["strict"] == .bool(true))
    guard case .array(let messages)? = body["messages"], case .array(let parts)? = messages[1]["content"] else {
        Issue.record("no messages")
        return
    }
    #expect(parts[1]["image_url"]?["url"] == .string("data:image/jpeg;base64,AQID"))
}

@Test func aKeyIsSentAsABearerToken() throws {
    let provider = ChatProvider(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", apiKey: "sk-test")
    let request = try provider.urlRequest(for: .altText, images: [], schema: ChatProvider.textSchema)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
}

@Test func badSetupsAreRefusedBeforeAnythingIsSent() {
    #expect(throws: ChatProvider.Failure.badURL) { try ChatProvider(baseURL: "not a url", model: "m").endpoint() }
    #expect(throws: ChatProvider.Failure.badURL) { try ChatProvider(baseURL: "ftp://host/v1", model: "m").endpoint() }
    #expect(throws: ChatProvider.Failure.notSet) { try ChatProvider(baseURL: "http://localhost:1234/v1", model: " ").urlRequest(for: .altText, images: [], schema: ChatProvider.textSchema) }
    let many = Array(repeating: ProviderImage(data: Data(), mimeType: "image/png"), count: 21)
    #expect(throws: ChatProvider.Failure.tooManyImages) { try ChatProvider(baseURL: "http://localhost:1234/v1", model: "m").urlRequest(for: .altText, images: many, schema: ChatProvider.textSchema) }
}

@Test func aValidReplyParses() throws {
    let parsed = try ChatProvider.parse(reply(#"{"text":"A window."}"#), status: 200, schema: ChatProvider.textSchema)
    #expect(parsed["text"] == .string("A window."))
}

@Test func aFencedReplyFromALocalModelParses() throws {
    let parsed = try ChatProvider.parse(reply("```json\n{\"text\":\"A window.\"}\n```"), status: 200, schema: ChatProvider.textSchema)
    #expect(parsed["text"] == .string("A window."))
}

@Test func malformedRepliesFailWithAReason() {
    let schema = ChatProvider.textSchema
    #expect(throws: ChatProvider.Failure.malformed("no choices")) { try ChatProvider.parse(Data("{}".utf8), status: 200, schema: schema) }
    #expect(throws: ChatProvider.Failure.malformed("no choices")) { try ChatProvider.parse(Data("nope".utf8), status: 200, schema: schema) }
    #expect(throws: ChatProvider.Failure.malformed("the content isn't JSON")) { try ChatProvider.parse(reply("A window."), status: 200, schema: schema) }
    #expect(throws: ChatProvider.Failure.malformed("no content")) { try ChatProvider.parse(reply(""), status: 200, schema: schema) }
    #expect(throws: (any Error).self) { try ChatProvider.parse(reply(#"{"caption":"A window."}"#), status: 200, schema: schema) }
    #expect(throws: (any Error).self) { try ChatProvider.parse(reply(#"{"text":3}"#), status: 200, schema: schema) }
}

@Test func serverErrorsAndRefusalsAreReported() {
    let error = Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)
    #expect(throws: ChatProvider.Failure.server(status: 401, message: "Invalid API key")) { try ChatProvider.parse(error, status: 401, schema: ChatProvider.textSchema) }
    #expect(throws: ChatProvider.Failure.server(status: 500, message: nil)) { try ChatProvider.parse(Data(), status: 500, schema: ChatProvider.textSchema) }
    let refusal = Data(#"{"choices":[{"message":{"content":null,"refusal":"No."}}]}"#.utf8)
    #expect(throws: ChatProvider.Failure.refused("No.")) { try ChatProvider.parse(refusal, status: 200, schema: ChatProvider.textSchema) }
}

@Test func largeImagesAreScaledAndKeptUnderTheLimits() throws {
    let context = try #require(CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
    let image = try #require(context.makeImage())
    let encoded = try #require(ProviderImage.encoding(image))
    #expect(encoded.mimeType == "image/jpeg")
    #expect(encoded.data.count < ProviderImage.maximumBytes)
    let decoded = try #require(ImageCodec.image(from: encoded.data))
    #expect(max(decoded.width, decoded.height) <= ProviderImage.maximumLongEdge)
}

@Test func theProviderKeyRoundTripsThroughTheKeychain() {
    let service = "dev.lorcan.Shot.provider.test.\(UUID().uuidString)"
    defer { ProviderKeychain.save("", service: service) }
    #expect(ProviderKeychain.load(service: service) == "")
    if ProviderKeychain.save("sk-one", service: service) {
        #expect(ProviderKeychain.load(service: service) == "sk-one")
        ProviderKeychain.save("sk-two", service: service)
        #expect(ProviderKeychain.load(service: service) == "sk-two")
        ProviderKeychain.save("", service: service)
        #expect(ProviderKeychain.load(service: service) == "")
    }
}

@Test func localPresetsComeFirst() {
    #expect(ProviderPreset.allCases.prefix(2).allSatisfy { $0.isLocal })
    #expect(ProviderPreset.allCases.dropFirst(2).allSatisfy { !$0.isLocal })
}
