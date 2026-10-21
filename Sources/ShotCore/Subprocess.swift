import Foundation
import Synchronization
#if canImport(Darwin)
import Darwin

/// `read(2)`, which `Subprocess.read(upTo:)` hides.
private let systemRead = Darwin.read
#elseif canImport(Glibc)
import Glibc

private let systemRead = Glibc.read
#endif

/// A program run with arguments and nothing on its standard input, its standard output read as it comes and its
/// standard error kept for the error it fails with. ShotCoreLinux runs ffmpeg and ffprobe through it.
///
/// It's spawned directly rather than through `Process`, whose `waitUntilExit` spins a thread of the pool, and with no
/// signals blocked, which it would otherwise inherit from the thread that starts it. Blocking reads and the wait for
/// it to end run on threads of its own, never the pool's.
public final class Subprocess: Sendable {
    /// How a program ended when it didn't succeed.
    public struct Failure: LocalizedError, Equatable, Sendable {
        /// The program's name.
        public let program: String
        /// Its exit status, 128 plus the signal that stopped it, or -1 when it couldn't start.
        public let status: Int32
        /// The last line it printed on standard error, or why it couldn't start.
        public let message: String

        public var errorDescription: String? {
            message.isEmpty ? "\(program) stopped with status \(status)" : "\(program): \(message)"
        }
    }

    public let program: String
    private let pid: pid_t
    private let output: Int32
    private let reads: DispatchQueue
    private let shared: Shared

    /// What the thread that waits for the program shares with the rest.
    private final class Shared: Sendable {
        struct State {
            /// The exit status once it's been reaped, after which its process ID may belong to another program.
            var status: Int32?
            var errors = Data()
            var waiting: [CheckedContinuation<Int32, Never>] = []
        }

        let state = Mutex(State())
    }

    /// The most of standard error kept, from its end.
    private static let keptErrors = 16 * 1024

    /// Starts `executable`, a path, with `arguments`. Throws `Failure` when it can't.
    public init(_ executable: String, _ arguments: [String]) throws(Failure) {
        program = URL(fileURLWithPath: executable).lastPathComponent
        let failure = { (error: Int32) in Failure(program: URL(fileURLWithPath: executable).lastPathComponent, status: -1, message: String(cString: strerror(error))) }
        let outputPipe = try Self.makePipe(failure)
        let errorPipe: (read: Int32, write: Int32)
        do {
            errorPipe = try Self.makePipe(failure)
        } catch {
            close(outputPipe.read)
            close(outputPipe.write)
            throw error
        }
        defer {
            close(outputPipe.write)
            close(errorPipe.write)
        }
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outputPipe.write, 1)
        posix_spawn_file_actions_adddup2(&actions, errorPipe.write, 2)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        // A program that's stopped reading from writes to a closed pipe, which should end it, as it would from a shell.
        var pipeSignal = sigset_t()
        sigemptyset(&pipeSignal)
        sigaddset(&pipeSignal, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &pipeSignal)
        // A group of its own, so stopping it stops whatever it started too, which may hold its output open.
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETPGROUP))
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { environment.forEach { free($0) } }
        var spawnedID = pid_t()
        let spawned = posix_spawn(&spawnedID, executable, &actions, &attributes, argv, environment)
        guard spawned == 0 else {
            close(outputPipe.read)
            close(errorPipe.read)
            throw failure(spawned)
        }
        let pid = spawnedID
        self.pid = pid
        output = outputPipe.read
        reads = DispatchQueue(label: "dev.lorcan.Shot.subprocess.output")
        shared = Shared()
        // Standard error is read to its end, which comes when the program ends, then the program is reaped. It's
        // waited for without reaping first, so `stop` never signals a process ID that's been reused.
        let (shared, errors) = (shared, errorPipe.read)
        DispatchQueue(label: "dev.lorcan.Shot.subprocess.wait").async {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = systemRead(errors, &buffer, buffer.count)
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    break
                }
                shared.state.withLock { state in
                    state.errors.append(contentsOf: buffer[..<count])
                    if state.errors.count > 2 * Self.keptErrors {
                        state.errors.removeFirst(state.errors.count - Self.keptErrors)
                    }
                }
            }
            close(errors)
            var info = siginfo_t()
            while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
            let waiting = shared.state.withLock { state in
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                // An exit puts its status in the second byte; a signal puts its number in the low seven bits.
                state.status = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + status & 0x7f
                defer { state.waiting = [] }
                return state.waiting.map { ($0, state.status!) }
            }
            for (continuation, status) in waiting {
                continuation.resume(returning: status)
            }
        }
    }

    deinit {
        stop()
        close(output)
    }

    /// A pipe whose ends close in any program spawned, so only the ends dup'd onto a program's standard output and
    /// error stay open in it.
    private static func makePipe(_ failure: (Int32) -> Failure) throws(Failure) -> (read: Int32, write: Int32) {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else {
            throw failure(errno)
        }
        for end in ends {
            _ = fcntl(end, F_SETFD, FD_CLOEXEC)
        }
        return (ends[0], ends[1])
    }

    /// Reads `count` bytes of what it prints, or fewer only where its output ends; none at the end.
    public func read(upTo count: Int) async -> Data {
        let output = output
        return await withCheckedContinuation { continuation in
            reads.async {
                var data = Data(count: count)
                var filled = 0
                data.withUnsafeMutableBytes { bytes in
                    while filled < count {
                        let read = systemRead(output, bytes.baseAddress! + filled, count - filled)
                        if read < 0, errno == EINTR {
                            continue
                        }
                        guard read > 0 else {
                            break
                        }
                        filled += read
                    }
                }
                data.count = filled
                continuation.resume(returning: data)
            }
        }
    }

    /// Kills it and whatever it started, unless it's ended.
    public func stop() {
        shared.state.withLock { state in
            if state.status == nil {
                kill(-pid, SIGKILL)
            }
        }
    }

    /// Waits for it to end, and throws `Failure` unless it ended with status 0.
    public func wait() async throws(Failure) {
        let shared = shared
        let status = await withCheckedContinuation { continuation in
            let status = shared.state.withLock { state in
                if state.status == nil {
                    state.waiting.append(continuation)
                }
                return state.status
            }
            if let status {
                continuation.resume(returning: status)
            }
        }
        guard status == 0 else {
            let errors = String(decoding: shared.state.withLock { $0.errors }, as: UTF8.self)
            let last = errors.split(whereSeparator: \.isNewline).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            throw Failure(program: program, status: status, message: last)
        }
    }

    /// Runs `executable` with `arguments`, handing it to `body` to read what it prints, then reads and drops whatever
    /// `body` left, so it never waits to write, and waits for it to end. It's killed when the task is cancelled or `body`
    /// throws. Throws `Failure` when it ends with any status but 0, and `CancellationError` when the task was cancelled.
    public static func run<T>(_ executable: String, _ arguments: [String], _ body: (Subprocess) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let process = try Subprocess(executable, arguments)
        let result: T
        do {
            result = try await withTaskCancellationHandler {
                let result = try await body(process)
                while await !process.read(upTo: 64 * 1024).isEmpty {}
                return result
            } onCancel: {
                process.stop()
            }
        } catch {
            process.stop()
            try? await process.wait()
            throw error
        }
        do {
            try await process.wait()
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        return result
    }

    /// Runs `executable` with `arguments` to its end and returns all it printed, as `run` does.
    public static func output(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await run(executable, arguments) { process in
            var data = Data()
            while true {
                let chunk = await process.read(upTo: 64 * 1024)
                data.append(chunk)
                if chunk.count < 64 * 1024 {
                    return data
                }
            }
        }
    }
}
