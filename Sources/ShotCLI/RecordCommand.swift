import Darwin
import Foundation
import ShotCore

extension ShotCLI {
    /// `shot record --window … -- <command>`: records `target` through the app while `arguments` runs, with its input
    /// and output passed straight through, then stops the recording and prints it with the command's exit code. Gives
    /// the code to exit with, which follows the command's.
    static func record(_ target: AgentTarget, running arguments: [String], program: String) async -> Int32 {
        let app = appBundle()
        // Listening before the recording starts, so a Ctrl-C while it starts still stops it.
        let signals = RecordSignals()
        let id: String?
        do {
            id = try await ask(AgentRequest(.record, target: target), app: app)["id"]?.string
        } catch {
            printError("\(program) record: \(error.message)")
            return error.exitCode
        }
        let recorded = target.display.map { "display \($0)" } ?? target.window ?? target.bundleID ?? "the window"
        printError("Recording \(recorded) while \(arguments[0]) runs.")
        let status: (code: Int32, signal: Int32?)
        if let signal = signals.received {
            status = (128 + signal, signal)
        } else {
            switch spawn(arguments) {
            case let .success(pid):
                signals.started(pid)
                status = RecordedCommand.exitCode(waitStatus: await wait(for: pid))
            case let .failure(failure):
                printError("\(program) record: \(failure.message)")
                status = (failure.code, nil)
            }
        }
        var recordingError: ShotCommandError?
        do {
            var result = try await ask(AgentRequest(.stop, id: id), app: app)
            result["exitCode"] = .number(Double(status.code))
            if let signal = status.signal {
                result["signal"] = .number(Double(signal))
            }
            print(ShotCommand.json(.object(result)))
            if let path = result["path"]?.string {
                printError("\(program) frames \"\(path)\" shows what happened in it.")
            }
        } catch {
            recordingError = error
            printError("\(program) record: the command exited with \(status.code), but \(error.message)")
        }
        return RecordedCommand.exitCode(command: status.code, recording: recordingError)
    }

    struct SpawnFailure: Error {
        /// 127 when the command isn't found and 126 when it can't run, as a shell exits.
        let code: Int32
        let message: String
    }

    /// Starts `arguments`, found on the PATH, in this process group, so a Ctrl-C at the terminal reaches it directly.
    /// It gets the signals Shot listens for back at their defaults, and the rest of its environment as Shot's.
    private static func spawn(_ arguments: [String]) -> Result<pid_t, SpawnFailure> {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in RecordSignals.handled {
            sigaddset(&defaults, signal)
        }
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid = pid_t()
        let result = posix_spawnp(&pid, arguments[0], nil, &attributes, argv, environ)
        guard result == 0 else {
            return .failure(SpawnFailure(code: result == ENOENT ? 127 : 126, message: "couldn't run \(arguments[0]): \(String(cString: strerror(result)))"))
        }
        return .success(pid)
    }

    /// Waits on a thread of its own for `pid` to end, and gives its `waitpid` status.
    private static func wait(for pid: pid_t) async -> Int32 {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                continuation.resume(returning: status)
            }
        }
    }
}

/// The signals that end `shot record -- <command>`, caught so the recording is always stopped. A Ctrl-C at the
/// terminal reaches the command too, since it shares Shot's process group, so Shot only waits for it to exit; a
/// termination or hang-up sent to Shot alone is passed on to the command.
final class RecordSignals: @unchecked Sendable {
    static let handled = [SIGINT, SIGTERM, SIGHUP]

    private let lock = NSLock()
    private var child: pid_t?
    private var first: Int32?
    private var sources: [DispatchSourceSignal] = []

    init() {
        for number in Self.handled {
            // A dispatch source sees the signal only once its default action, ending Shot, is off.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                self?.receive(number)
            }
            source.resume()
            sources.append(source)
        }
    }

    /// The first signal that came, if any.
    var received: Int32? {
        lock.withLock { first }
    }

    /// Passes on to `pid` from now on, and at once if a termination came while it started.
    func started(_ pid: pid_t) {
        let pending = lock.withLock {
            child = pid
            return first
        }
        if let pending, pending != SIGINT {
            kill(pid, pending)
        }
    }

    private func receive(_ number: Int32) {
        let pid = lock.withLock {
            first = first ?? number
            return child
        }
        if let pid, number != SIGINT {
            kill(pid, number)
        }
    }
}
