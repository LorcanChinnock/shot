import Foundation
@testable import ShotCore

/// Starts and stops the servers the tests run against, such as Xvfb and a D-Bus bus. They're spawned directly rather
/// than through `Process`, whose `waitUntilExit` spins a thread of the pool the other tests need, and with no signals
/// blocked, since the test's threads block SIGTERM and the server would keep that.
enum TestServer {
    /// Starts `executable` with `arguments`, its output thrown away, and this process's environment with `environment`
    /// added.
    static func spawn(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) throws -> pid_t {
        var attributes = posix_spawnattr_t()
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK))
        var actions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let variables = ProcessInfo.processInfo.environment.merging(environment) { $1 }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { variables.forEach { free($0) } }
        var pid: pid_t = 0
        let error = posix_spawn(&pid, executable, &actions, &attributes, argv, variables)
        guard error == 0 else {
            throw ShotCommandError.internal("Couldn't start \(executable): \(String(cString: strerror(error))).")
        }
        return pid
    }

    /// Asks the server to quit, which lets it clean up after itself, and waits for it.
    static func stop(_ pid: pid_t) {
        kill(pid, SIGTERM)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    /// Whether the server is still running.
    static func isRunning(_ pid: pid_t) -> Bool {
        var status: Int32 = 0
        return waitpid(pid, &status, WNOHANG) == 0
    }

    /// The first of `paths` that can be run.
    static func executable(_ paths: String...) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
