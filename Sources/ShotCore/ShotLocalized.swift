import Foundation

#if canImport(Darwin)
/// The text the user reads for `value`, in their language. Every string ShotCore shows goes through here rather than
/// `String(localized:)`, which Linux doesn't have. The build still extracts the literal into the catalog, because it
/// finds strings by their `String.LocalizationValue` type rather than by the call.
public func shotLocalized(_ value: String.LocalizationValue) -> String {
    String(localized: value)
}
#else
/// The English text for `value`, from the table `scripts/strings.sh` writes from `Resources/Localizable.xcstrings`.
public func shotLocalized(_ value: LocalizationValue) -> String {
    let forms = localizableEnglish[value.key]
    let count = value.arguments.lazy.compactMap { if case let .integer(count) = $0 { count } else { nil } }.first
    let format = (count == 1 ? forms?["one"] : nil) ?? forms?["other"] ?? value.key
    return value.arguments.isEmpty ? format : LocalizationValue.formatted(format, value.arguments)
}

/// Linux's stand-in for `String.LocalizationValue`: a literal and its interpolations, as the catalog key the Apple type
/// makes of them (`"Step \(n)"` is `"Step %lld"`) and the values to put back.
public struct LocalizationValue: ExpressibleByStringInterpolation, Sendable {
    public enum Argument: Equatable, Sendable {
        case string(String)
        case integer(Int)
    }

    public let key: String
    public let arguments: [Argument]

    /// A literal without interpolations is its own key, `%` and all, as with the Apple type.
    public init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [Argument] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + 4 * interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }

        public mutating func appendInterpolation(_ value: String) {
            key += "%@"
            arguments.append(.string(value))
        }

        public mutating func appendInterpolation(_ value: Int) {
            key += "%lld"
            arguments.append(.integer(value))
        }
    }

    /// `format` with each specifier, in order or by position (`%2$@`), replaced by its argument, and `%%` by `%`.
    static func formatted(_ format: String, _ arguments: [Argument]) -> String {
        var result = ""
        var next = 0
        var rest = Substring(format)
        while let percent = rest.firstIndex(of: "%") {
            result += rest[..<percent]
            rest = rest[rest.index(after: percent)...]
            if rest.first == "%" {
                result += "%"
                rest = rest.dropFirst()
                continue
            }
            var index = next
            let digits = rest.prefix(while: \.isNumber)
            if !digits.isEmpty, rest.dropFirst(digits.count).first == "$", let position = Int(digits) {
                index = position - 1
                rest = rest.dropFirst(digits.count + 1)
            } else {
                next += 1
            }
            rest = rest.drop(while: { "hlqjzt".contains($0) }).dropFirst()
            switch index < arguments.count ? arguments[index] : nil {
            case let .string(value): result += value
            case let .integer(value): result += String(value)
            case nil: break
            }
        }
        return result + rest
    }
}
#endif
