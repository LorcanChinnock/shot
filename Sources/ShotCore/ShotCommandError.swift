import Foundation

/// Why a `shot` command failed, and the exit code it ends with, following `sysexits.h`.
public enum ShotCommandError: Error, Equatable, Sendable {
    /// A bad flag, a missing argument or a value out of range; the command it was for, if any.
    case usage(String?, String)
    /// Not an image or video Shot can read, marks that don't make sense, or a rect off the image.
    case data(String)
    /// The input file isn't there.
    case noInput(String)
    /// The output can't be made: it exists, or its folder doesn't or isn't writable.
    case cantCreate(String)
    /// Reading or writing failed partway.
    case io(String)
    case `internal`(String)
    /// Shot isn't running, or Let agents capture and record is off, so nothing answers.
    case unavailable(String)
    /// Shot is in the middle of something it can't share: a selection, the recording setup, or a recording.
    case busy(String)
    /// Shot doesn't have the Screen Recording permission.
    case noPermission(String)

    public var exitCode: Int32 {
        switch self {
        case .usage: 64
        case .data: 65
        case .noInput: 66
        case .unavailable: 69
        case .internal: 70
        case .cantCreate: 73
        case .io: 74
        case .busy: 75
        case .noPermission: 77
        }
    }

    public var message: String {
        switch self {
        case let .usage(_, message), let .data(message), let .noInput(message), let .cantCreate(message), let .io(message), let .internal(message),
             let .unavailable(message), let .busy(message), let .noPermission(message):
            message
        }
    }

    /// The error with `exitCode`, as the app sends it back to the command line; an unknown code is `.internal`.
    public init(exitCode: Int32, message: String) {
        self = switch exitCode {
        case 64: .usage(nil, message)
        case 65: .data(message)
        case 66: .noInput(message)
        case 69: .unavailable(message)
        case 73: .cantCreate(message)
        case 74: .io(message)
        case 75: .busy(message)
        case 77: .noPermission(message)
        default: .internal(message)
        }
    }
}
