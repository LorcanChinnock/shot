import Foundation

/// The D-Bus values the desktop portal takes and gives, which ShotCoreLinux's `SessionBus` writes and reads through
/// libdbus. They're here so what the portal answers can be read and tested without a bus. A dictionary is `a{sv}`, whose
/// values come out of their variants.
public indirect enum BusValue: Equatable, Sendable {
    case string(String)
    case objectPath(String)
    case bool(Bool)
    case uint32(UInt32)
    case int32(Int32)
    /// A file descriptor, which whoever reads it owns.
    case unixFD(Int32)
    case variant(BusValue)
    case dictionary([String: BusValue])
    case array([BusValue])
    case structure([BusValue])

    public var signature: String {
        switch self {
        case .string: "s"
        case .objectPath: "o"
        case .bool: "b"
        case .uint32: "u"
        case .int32: "i"
        case .unixFD: "h"
        case .variant: "v"
        case .dictionary: "a{sv}"
        case let .array(values): "a" + (values.first?.signature ?? "v")
        case let .structure(values): "(" + values.map(\.signature).joined() + ")"
        }
    }
}
