import CPipeWireStream
import Foundation
import Synchronization

/// Reads a screen cast's video from PipeWire, through `CPipeWireStream`, on a thread of PipeWire's own: each frame
/// goes to `frame` there, its rows lasting only until it returns, and why the stream ended to `ended`, once.
final class PipeWireStream: Sendable {
    /// A frame's first row, its width and height in pixels, the bytes from one row to the next, and its layout, numbered
    /// as `FFmpeg.castPixelFormats`.
    typealias Frame = @Sendable (_ pixels: UnsafeRawPointer, _ width: Int, _ height: Int, _ stride: Int, _ format: Int) -> Void

    /// What the C callbacks reach through their context.
    private final class Handlers: Sendable {
        let frame: Frame
        let ended: @Sendable (String) -> Void

        init(frame: @escaping Frame, ended: @escaping @Sendable (String) -> Void) {
            self.frame = frame
            self.ended = ended
        }
    }

    private let handlers: Handlers
    /// The C stream, until it's stopped.
    private let stream: Mutex<OpaquePointer?>

    /// Connects through `fd`, which `OpenPipeWireRemote` gave and which this takes, and reads `node` at up to
    /// `frameRate` frames a second.
    init(fd: Int32, node: UInt32, frameRate: Int, frame: @escaping Frame, ended: @escaping @Sendable (String) -> Void) throws(ShotCommandError) {
        handlers = Handlers(frame: frame, ended: ended)
        // Kept from the programs Shot starts, so only PipeWire holds the connection.
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var error = [CChar](repeating: 0, count: 512)
        let context = Unmanaged.passUnretained(handlers).toOpaque()
        let started = shot_pw_stream_start(fd, node, UInt32(max(1, frameRate)), { context, pixels, width, height, stride, format in
            guard let context, let pixels else {
                return
            }
            Unmanaged<Handlers>.fromOpaque(context).takeUnretainedValue().frame(UnsafeRawPointer(pixels), Int(width), Int(height), Int(stride), Int(format.rawValue))
        }, { context, reason in
            guard let context else {
                return
            }
            Unmanaged<Handlers>.fromOpaque(context).takeUnretainedValue().ended(reason.map { String(cString: $0) } ?? "the screen cast ended")
        }, context, &error, error.count)
        guard let started else {
            throw .unavailable("Shot couldn't read the screen cast from PipeWire: \(String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).")
        }
        stream = Mutex(started)
    }

    deinit {
        stop()
    }

    /// Stops reading, after which neither callback is called. Never call it from one.
    func stop() {
        let running = stream.withLock { stream in
            defer { stream = nil }
            return stream
        }
        shot_pw_stream_stop(running)
    }

    /// The version of libpipewire that's loaded, such as `1.0.5`.
    static var libraryVersion: String {
        String(cString: shot_pw_library_version())
    }
}
