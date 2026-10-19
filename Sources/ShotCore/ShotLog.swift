import Foundation

#if canImport(os)
import os

/// ShotCore's logger: the unified log on Apple platforms, standard error elsewhere, with the same calls on both.
public typealias ShotLog = Logger

extension Logger {
    /// Logs under the app's bundle identifier, so forks with their own identifier keep their logs apart.
    public static func shot(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shot", category: category)
    }
}
#else
/// ShotCore's logger where there's no unified log: it writes each message to standard error. It takes the calls ShotCore
/// makes of `Logger`, privacy included, though standard error shows every value.
public struct ShotLog: Sendable {
    public let subsystem: String
    public let category: String

    public static func shot(_ category: String) -> ShotLog {
        ShotLog(subsystem: Bundle.main.bundleIdentifier ?? "Shot", category: category)
    }

    public func error(_ message: Message) {
        FileHandle.standardError.write(Data("[\(subsystem):\(category)] error: \(message.text)\n".utf8))
    }

    public enum Privacy: Sendable {
        case auto, `public`, `private`
    }

    public struct Message: ExpressibleByStringInterpolation, Sendable {
        let text: String

        public init(stringLiteral value: String) {
            text = value
        }

        public init(stringInterpolation: StringInterpolation) {
            text = stringInterpolation.text
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            var text = ""

            public init(literalCapacity: Int, interpolationCount: Int) {
                text.reserveCapacity(literalCapacity)
            }

            public mutating func appendLiteral(_ literal: String) {
                text += literal
            }

            public mutating func appendInterpolation(_ value: some Any, privacy: Privacy = .auto) {
                text += String(describing: value)
            }
        }
    }
}
#endif
