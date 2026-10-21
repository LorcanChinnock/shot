#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// The Unix socket the running app answers agents on, so `shot capture` can ask it for a screenshot: Screen Recording
/// belongs to the app, not to a terminal. One `AgentRequest` line per connection, then one `AgentResponse` line, then
/// the connection closes. Only the same user can connect: the folder is 0700, the socket 0600, and each peer is checked.
public enum AgentSocket {
    /// The longest request the server reads; anything longer is refused.
    public static let maximumRequest = 64 * 1024
    /// How long the server waits for a client to send its request.
    static let requestTimeout = Duration.seconds(5)

    /// `agent.sock` in the app's support folder, so Shot and ShotDev never answer each other's agents.
    public static func url(bundleID: String) -> URL {
        AppSupport.folder(bundleID: bundleID).appendingPathComponent("agent.sock")
    }

    /// Accepts connections on a queue of its own, and hands each request to `handler`.
    public final class Server: @unchecked Sendable {
        public typealias Handler = @Sendable (AgentRequest) async -> AgentResponse

        public let url: URL
        /// The only user whose connections are answered: this one, but for tests of the check.
        let user: uid_t
        private let handler: Handler
        private let queue = DispatchQueue(label: "dev.lorcan.Shot.agent-socket")
        /// Read and written on `queue` only.
        private var source: DispatchSourceRead?

        public convenience init(url: URL, handler: @escaping Handler) {
            self.init(url: url, user: getuid(), handler: handler)
        }

        init(url: URL, user: uid_t, handler: @escaping Handler) {
            self.url = url
            self.user = user
            self.handler = handler
        }

        /// Makes the folder and the socket and starts listening. A socket left by a run that died is replaced, but one
        /// another process still answers on is left alone, as `.busy`.
        public func start() throws(ShotCommandError) {
            var address = try AgentSocket.address(of: url)
            let folder = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Set every time, so a folder made looser by hand is closed again.
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            } catch {
                throw .cantCreate("couldn't make \(folder.path): \(error.localizedDescription)")
            }
            var info = stat()
            if lstat(url.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFSOCK else {
                    throw .cantCreate("\(url.path) is in the way and isn't a socket")
                }
                guard !AgentSocket.isListening(at: url) else {
                    throw .busy("another copy of Shot is already answering agents at \(url.path)")
                }
                unlink(url.path)
            }
            let fd = socket(AF_UNIX, AgentSocket.stream, 0)
            guard fd >= 0 else {
                throw .io("couldn't make a socket: \(AgentSocket.reason())")
            }
            // Kept from the programs Shot starts, such as the ffmpeg that records, which would otherwise hold it open.
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, chmod(url.path, 0o600) == 0, listen(fd, 16) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                let reason = AgentSocket.reason()
                close(fd)
                unlink(url.path)
                throw .cantCreate("couldn't listen at \(url.path): \(reason)")
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptAll(on: fd)
            }
            source.setCancelHandler {
                close(fd)
            }
            queue.sync {
                self.source?.cancel()
                self.source = source
            }
            source.resume()
        }

        /// Stops listening and removes the socket. Requests already being answered still get their answer.
        public func stop() {
            let wasListening = queue.sync {
                let listening = source != nil
                source?.cancel()
                source = nil
                return listening
            }
            if wasListening {
                unlink(url.path)
            }
        }

        private func acceptAll(on fd: Int32) {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    return
                }
                // Accepted sockets inherit the listener's O_NONBLOCK, but not its FD_CLOEXEC; this one is read with a
                // timeout instead.
                _ = fcntl(client, F_SETFL, 0)
                _ = fcntl(client, F_SETFD, FD_CLOEXEC)
                AgentSocket.keepSignalsOff(client)
                guard AgentSocket.peerUser(of: client) == user else {
                    close(client)
                    continue
                }
                let handler = handler
                // A thread of its own, since the global queues' threads can all be busy.
                Thread.detachNewThread {
                    Self.serve(client, handler: handler)
                }
            }
        }

        /// Reads one request from `client`, answers it, and closes it. Blocks, so it runs off the accepting queue.
        private static func serve(_ client: Int32, handler: @escaping Handler) {
            AgentSocket.setTimeout(client, SO_RCVTIMEO, AgentSocket.requestTimeout)
            AgentSocket.setTimeout(client, SO_SNDTIMEO, AgentSocket.requestTimeout)
            let request: AgentRequest
            switch AgentSocket.readLine(client, limit: AgentSocket.maximumRequest, deadline: .now + AgentSocket.requestTimeout) {
            case let .line(data):
                do {
                    request = try AgentRequest.decode(data)
                } catch {
                    AgentSocket.reply(.failure(error), to: client)
                    return
                }
            case .tooLong:
                AgentSocket.reply(.failure(.usage(nil, "the request is over \(AgentSocket.maximumRequest / 1024) KB")), to: client)
                return
            case .closed, .timedOut, .failed:
                close(client)
                return
            }
            // On a queue of its own: a serial queue, unlike the global ones, gets a thread even when all of theirs are busy.
            let queue = DispatchQueue(label: "dev.lorcan.Shot.agent-socket.answer")
            queue.setSpecific(key: answering, value: true)
            Task(executorPreference: QueueExecutor(queue)) {
                AgentSocket.reply(await handler(request), to: client)
            }
        }
    }

    /// Marks the queues requests are answered on.
    static let answering = DispatchSpecificKey<Bool>()

    /// Runs tasks' jobs on a queue rather than the threads of the shared pool, so an agent's answer never waits for work
    /// that holds every one of those, such as tests drawing pictures in parallel.
    final class QueueExecutor: TaskExecutor {
        private let queue: DispatchQueue

        init(_ queue: DispatchQueue) {
            self.queue = queue
        }

        func enqueue(_ job: consuming ExecutorJob) {
            let job = UnownedJob(job)
            queue.async {
                job.runSynchronously(on: self.asUnownedTaskExecutor())
            }
        }
    }

    /// Sends `request` to the app listening at `url` and waits up to `timeout` for its answer.
    public static func send(_ request: AgentRequest, to url: URL, timeout: Duration) async throws(ShotCommandError) -> [String: JSONValue] {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<AgentResponse, ShotCommandError>, Never>) in
            DispatchQueue.global().async {
                continuation.resume(returning: Result { () throws(ShotCommandError) in try exchange(request, at: url, timeout: timeout) })
            }
        }
        return try result.get().get()
    }

    /// Whether something answers at `url`.
    public static func isListening(at url: URL) -> Bool {
        guard let fd = try? connect(to: url) else {
            return false
        }
        close(fd)
        return true
    }

    /// The blocking half of `send`.
    private static func exchange(_ request: AgentRequest, at url: URL, timeout: Duration) throws(ShotCommandError) -> AgentResponse {
        let fd = try connect(to: url)
        defer { close(fd) }
        keepSignalsOff(fd)
        setTimeout(fd, SO_SNDTIMEO, requestTimeout)
        // A write the app cut short, because the request was too long, still leaves its answer to read.
        _ = write(request.line, to: fd)
        switch readLine(fd, limit: 16 * 1024 * 1024, deadline: .now + timeout) {
        case let .line(data):
            return try AgentResponse.decode(data)
        case .timedOut:
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            throw .unavailable("Shot didn't answer within \(String(format: "%g", seconds)) seconds. Check that it isn't waiting on a dialog, such as a permission prompt, then try again.")
        case .closed, .tooLong, .failed:
            throw .io("Shot closed the connection without a usable answer")
        }
    }

    private static func connect(to url: URL) throws(ShotCommandError) -> Int32 {
        var address = try address(of: url)
        let fd = socket(AF_UNIX, stream, 0)
        guard fd >= 0 else {
            throw .io("couldn't make a socket: \(reason())")
        }
        // Kept from the command `shot record` runs.
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                #if canImport(Darwin)
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #else
                Glibc.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #endif
            }
        }
        guard connected == 0 else {
            close(fd)
            #if os(Linux)
            throw .unavailable("shot serve isn't answering agents at \(url.path)")
            #else
            throw .unavailable("Shot isn't answering agents: it isn't running, or Settings › Agents › Let agents capture and record is off")
            #endif
        }
        return fd
    }

    /// The `sockaddr_un` for `url`, whose path must fit in `sun_path`, ending zero included.
    static func address(of url: URL) throws(ShotCommandError) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        let path = Array(url.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.count < capacity else {
            throw .cantCreate("the socket's path, \(url.path), is \(path.count) bytes; a socket's path can be at most \(capacity - 1)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        return address
    }

    private static func reply(_ response: AgentResponse, to client: Int32) {
        _ = write(response.line, to: client)
        close(client)
    }

    /// Writes all of `data`; false if the other end went away or stopped reading.
    private static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                #if canImport(Darwin)
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                #else
                let written = Glibc.send(fd, buffer.baseAddress! + offset, buffer.count - offset, Int32(MSG_NOSIGNAL))
                #endif
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    enum ReadResult {
        case line(Data)
        case tooLong, closed, timedOut, failed
    }

    /// Reads up to the first newline, giving up past `limit` bytes or at `deadline`.
    static func readLine(_ fd: Int32, limit: Int, deadline: ContinuousClock.Instant) -> ReadResult {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = deadline - .now
            guard remaining > .zero else {
                return .timedOut
            }
            setTimeout(fd, SO_RCVTIMEO, remaining)
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                return errno == EAGAIN || errno == EWOULDBLOCK ? .timedOut : .failed
            }
            if count == 0 {
                return .closed
            }
            if let newline = chunk[..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: chunk[..<newline])
                return data.count <= limit ? .line(data) : .tooLong
            }
            data.append(contentsOf: chunk[..<count])
            if data.count > limit {
                return .tooLong
            }
        }
    }

    /// Sets a send or receive timeout of at least a millisecond, since zero would mean none.
    static func setTimeout(_ fd: Int32, _ option: Int32, _ duration: Duration) {
        let (seconds, attoseconds) = max(duration, .milliseconds(1)).components
        var value = timeval(tv_sec: Int(seconds), tv_usec: suseconds_t(attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func reason() -> String {
        String(cString: strerror(errno))
    }

    #if canImport(Darwin)
    static let stream = SOCK_STREAM
    #else
    static let stream = Int32(SOCK_STREAM.rawValue)
    #endif

    /// Stops writes to `fd` raising `SIGPIPE` when its peer goes away, which would end the process. Linux passes
    /// `MSG_NOSIGNAL` to each `send` instead.
    static func keepSignalsOff(_ fd: Int32) {
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    /// The user at the other end of the connected socket `fd`, which the server checks is this one; `nil` when it can't tell.
    static func peerUser(of fd: Int32) -> uid_t? {
        #if canImport(Darwin)
        var uid = uid_t()
        var gid = gid_t()
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
        #else
        // Glibc's `struct ucred`, which it shows Swift only with `_GNU_SOURCE`.
        var credentials: (pid: pid_t, uid: uid_t, gid: gid_t) = (0, 0, 0)
        var size = socklen_t(MemoryLayout.size(ofValue: credentials))
        return getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &credentials, &size) == 0 ? credentials.uid : nil
        #endif
    }
}

extension AgentSocket {
    /// How long `ask` waits for an app it started to begin answering.
    static let launchTimeout = Duration.seconds(5)

    #if os(Linux)
    public static let turnedOff = "Shot isn't taking requests from agents. Run shot settings agent-capture on to let them capture, then try again."
    #else
    public static let turnedOff = "Shot isn't taking requests from agents. Turn on Settings › Agents › Let agents capture and record in Shot, then try again."
    #endif

    /// Sends `request` to the app with `bundleID`, first opening it in the background, without taking focus, when
    /// nothing answers. `enabled` is Let agents capture and record as the app's settings have it, so a setting that's off
    /// fails at once rather than after a launch, for a request that needs it.
    public static func ask(_ request: AgentRequest, bundleID: String, enabled: Bool, timeout: Duration) async throws(ShotCommandError) -> [String: JSONValue] {
        guard enabled || !request.op.needsAgentCapture else {
            throw .unavailable(turnedOff)
        }
        let url = url(bundleID: bundleID)
        if !isListening(at: url) {
            try launch(bundleID)
            let deadline = ContinuousClock.now + launchTimeout
            while !isListening(at: url) {
                guard ContinuousClock.now < deadline else {
                    #if os(Linux)
                    throw .unavailable("shot serve didn't start answering agents within \(launchTimeout.components.seconds) seconds. Run shot serve to see why.")
                    #else
                    throw .unavailable("Shot didn't start answering agents within \(launchTimeout.components.seconds) seconds. Check that it opens, and that Settings › Agents › Let agents capture and record is on.")
                    #endif
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return try await send(request, to: url, timeout: timeout)
    }

    /// Opens the app with `bundleID` in the background, as `open -g` does, which does nothing when it's running. Linux
    /// has no app, so it starts `shot serve` instead: this executable, which is `shot`, in a session of its own, so it
    /// outlives the terminal or the agent that started it, with nothing on its standard input and output, which may be
    /// an MCP client's pipes.
    private static func launch(_ bundleID: String) throws(ShotCommandError) {
        #if os(Linux)
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        for fd: Int32 in [0, 1, 2] {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        // Glibc's POSIX_SPAWN_SETSID, which it shows Swift only with `_GNU_SOURCE`.
        posix_spawnattr_setflags(&attributes, 0x80)
        let executable = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? "/proc/self/exe"
        let arguments = [executable, "serve"]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid = pid_t()
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
        guard spawned == 0 else {
            throw .unavailable("couldn't start shot serve: \(String(cString: strerror(spawned)))")
        }
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-b", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw .unavailable("couldn't open Shot (\(bundleID)): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw .unavailable("couldn't open Shot: no app with the bundle ID \(bundleID) is installed")
        }
        #endif
    }
}
