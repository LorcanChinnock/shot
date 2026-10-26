import Foundation

/// Any JSON value, for the parts of an MCP message whose shape the server doesn't fix.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        // Whole numbers go out without a fraction, so an id of 1 comes back as 1, not 1.0.
        case let .number(value) where value.rounded() == value && abs(value) < 1e15: try container.encode(Int64(value))
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var string: String? {
        if case let .string(value) = self { value } else { nil }
    }

    /// A number, or a string that reads as one, since agents sometimes quote them.
    public var number: Double? {
        switch self {
        case let .number(value): value
        case let .string(value): Double(value.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { object[key] } else { nil }
    }
}
