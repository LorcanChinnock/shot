import Foundation

/// The JSON Schema subset every OpenAI-compatible provider accepts for `strict` structured output, and a validator for
/// replies: Ollama and LM Studio may not enforce `strict`, so Shot checks every reply itself.
///
/// Allowed: an object at the root; on every object `properties`, every key in `required` and `additionalProperties:
/// false`; `string`, `integer`, `number`, `boolean` and `array` with `items`; `["string", "null"]` for an optional value;
/// flat string enums; nesting of at most 3 levels. Everything else (`oneOf`, `allOf`, `$ref`, `pattern`, `format`,
/// `default`, `const`, length limits) is rejected.
public enum ProviderSchema {
    public static let maximumDepth = 3
    static let allowedKeywords: Set = ["type", "properties", "required", "additionalProperties", "items", "enum", "description"]
    static let scalarTypes: Set = ["string", "integer", "number", "boolean"]

    /// What's wrong with `schema` for a strict provider, or `nil` when it's fine.
    public static func problem(with schema: JSONValue) -> String? {
        guard case .object = schema, schema["type"] == .string("object") else {
            return "The root must be an object"
        }
        return problem(with: schema, depth: 1, path: "root")
    }

    private static func problem(with schema: JSONValue, depth: Int, path: String) -> String? {
        guard case .object(let fields) = schema else {
            return "\(path) isn't a schema"
        }
        if let keyword = fields.keys.sorted().first(where: { !allowedKeywords.contains($0) }) {
            return "\(path) uses \(keyword), which not every provider accepts"
        }
        let types = typeNames(fields["type"])
        guard !types.isEmpty else {
            return "\(path) has no type"
        }
        if types.count == 2 {
            guard types.contains("null"), let other = types.first(where: { $0 != "null" }), scalarTypes.contains(other) else {
                return "\(path) can only be a scalar or null"
            }
        }
        if let values = fields["enum"] {
            guard case .array(let cases) = values, !cases.isEmpty, cases.allSatisfy({ $0.string != nil }), types.contains("string") else {
                return "\(path) has an enum that isn't a flat list of strings"
            }
        }
        if types.contains("object") {
            guard depth <= maximumDepth else {
                return "\(path) is nested more than \(maximumDepth) levels deep"
            }
            guard case .object(let properties)? = fields["properties"] else {
                return "\(path) has no properties"
            }
            guard fields["additionalProperties"] == .bool(false) else {
                return "\(path) must set additionalProperties to false"
            }
            guard case .array(let required)? = fields["required"], Set(required.compactMap(\.string)) == Set(properties.keys) else {
                return "\(path) must list every property in required"
            }
            for key in properties.keys.sorted() {
                if let problem = problem(with: properties[key]!, depth: depth + 1, path: "\(path).\(key)") {
                    return problem
                }
            }
        }
        if types.contains("array") {
            guard depth <= maximumDepth else {
                return "\(path) is nested more than \(maximumDepth) levels deep"
            }
            guard let items = fields["items"] else {
                return "\(path) has no items"
            }
            return problem(with: items, depth: depth + 1, path: "\(path)[]")
        }
        return nil
    }

    private static func typeNames(_ type: JSONValue?) -> [String] {
        switch type {
        case .string(let name)?: [name]
        case .array(let names)?: names.compactMap(\.string)
        default: []
        }
    }

    /// What's wrong with `value` as a reply to `schema`, or `nil` when it fits.
    public static func problem(with value: JSONValue, against schema: JSONValue, path: String = "reply") -> String? {
        let types = typeNames(schema["type"])
        switch value {
        case .null:
            return types.contains("null") ? nil : "\(path) is null"
        case .bool:
            return types.contains("boolean") ? nil : "\(path) should not be a boolean"
        case .number(let number):
            return types.contains("number") || (types.contains("integer") && number == number.rounded()) ? nil : "\(path) should be \(types.joined(separator: " or ")), not a number"
        case .string(let text):
            guard types.contains("string") else {
                return "\(path) should not be a string"
            }
            if case .array(let cases)? = schema["enum"], !cases.contains(.string(text)) {
                return "\(path) isn't one of the allowed values"
            }
            return nil
        case .array(let items):
            guard types.contains("array"), let itemSchema = schema["items"] else {
                return "\(path) should not be a list"
            }
            for (index, item) in items.enumerated() {
                if let problem = problem(with: item, against: itemSchema, path: "\(path)[\(index)]") {
                    return problem
                }
            }
            return nil
        case .object(let fields):
            guard types.contains("object"), case .object(let properties)? = schema["properties"] else {
                return "\(path) should not be an object"
            }
            if let extra = fields.keys.sorted().first(where: { properties[$0] == nil }) {
                return "\(path) has an unexpected \(extra)"
            }
            for key in properties.keys.sorted() {
                guard let field = fields[key] else {
                    return "\(path) is missing \(key)"
                }
                if let problem = problem(with: field, against: properties[key]!, path: "\(path).\(key)") {
                    return problem
                }
            }
            return nil
        }
    }
}
