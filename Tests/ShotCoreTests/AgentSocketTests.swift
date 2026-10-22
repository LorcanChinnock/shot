import Darwin
import Foundation
import Synchronization
import Testing
@testable import ShotCore

/// A short folder of its own, since a socket's whole path must fit in 103 bytes.
private func socketURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("agent.sock")
}

/// A server that answers each request with its op and window, after `delay`.
private func echoServer(at url: URL, delay: Duration = .zero) -> AgentSocket.Server {
    AgentSocket.Server(url: url) { request in
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return .success(["op": .string(request.op.rawValue), "window": .string(request.window ?? "")])
    }
}

private func failure(_ request: AgentRequest, at url: URL, timeout: Duration = .seconds(5)) async -> ShotCommandError? {
    do {
        _ = try await AgentSocket.send(request, to: url, timeout: timeout)
        return nil
    } catch {
        return error
    }
}

private func permissions(_ path: String) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
}

@Test func aRequestGetsItsAnswer() async throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    let answer = try await AgentSocket.send(AgentRequest(.capture, window: "Simulator"), to: url, timeout: .seconds(5))
    #expect(answer == ["op": .string("capture"), "window": .string("Simulator")])
    #expect(AgentSocket.isListening(at: url))
}

@Test func theAppsErrorComesBackWithItsCode() async throws {
    let url = try socketURL()
    let server = AgentSocket.Server(url: url) { _ in .failure(.busy("recording")) }
    try server.start()
    defer { server.stop() }
    #expect(await failure(AgentRequest(.status), at: url) == .busy("recording"))
}

@Test func onlyTheUserCanReachTheFolderAndTheSocket() async throws {
    let url = try socketURL()
    let folder = url.deletingLastPathComponent().path
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    #expect(try permissions(folder) == 0o700)
    #expect(try permissions(url.path) == 0o600)
}

@Test func aSocketLeftByADeadRunIsReplaced() async throws {
    let url = try socketURL()
    // Bound and closed without being removed, as a crash leaves it.
    var address = try AgentSocket.address(of: url)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    close(fd)
    #expect(bound == 0)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(!AgentSocket.isListening(at: url))
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    #expect(try await AgentSocket.send(AgentRequest(.status), to: url, timeout: .seconds(5))["op"] == .string("status"))
}

@Test func aLiveSocketIsntTakenOver() async throws {
    let url = try socketURL()
    let first = echoServer(at: url)
    try first.start()
    defer { first.stop() }
    let second = echoServer(at: url)
    #expect(throws: ShotCommandError.busy("another copy of Shot is already answering agents at \(url.path)")) {
        try second.start()
    }
    #expect(try await AgentSocket.send(AgentRequest(.status), to: url, timeout: .seconds(5))["op"] == .string("status"))
}

@Test func anOversizedRequestIsRefused() async throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    let huge = AgentRequest(.capture, window: String(repeating: "a", count: AgentSocket.maximumRequest + 10))
    #expect(await failure(huge, at: url) == .usage(nil, "the request is over 64 KB"))
}

@Test func nothingListeningIsUnavailable() async throws {
    let url = try socketURL()
    let error = try #require(await failure(AgentRequest(.status), at: url))
    #expect(error.exitCode == 69)
}

@Test func aSlowAnswerArrivesWithinTheTimeoutAndALateOneTimesOut() async throws {
    let url = try socketURL()
    let server = echoServer(at: url, delay: .milliseconds(400))
    try server.start()
    defer { server.stop() }
    #expect(try await AgentSocket.send(AgentRequest(.capture, window: "slow"), to: url, timeout: .seconds(5))["window"] == .string("slow"))
    #expect(await failure(AgentRequest(.status), at: url, timeout: .milliseconds(100)) == .unavailable("Shot didn't answer within 0.1 seconds. Check that it isn't waiting on a dialog, such as a permission prompt, then try again."))
}

/// Counts how many requests have reached the handler, so a test can wait for the rest without timing anything.
private actor Arrivals {
    private(set) var count = 0

    func arrive() {
        count += 1
    }
}

@Test func severalClientsAreAnsweredAtOnce() async throws {
    let url = try socketURL()
    let clients = 8
    let arrivals = Arrivals()
    // Each handler waits until every client has reached it, so the answers only come back if they're served in parallel.
    // A serial server leaves the first one waiting out its deadline, and the clients then time out. Nothing here depends
    // on how fast a loaded runner is, only on whether the clients overlap.
    let server = AgentSocket.Server(url: url) { request in
        await arrivals.arrive()
        let deadline = ContinuousClock.now + .seconds(10)
        while await arrivals.count < clients, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return .success(["op": .string(request.op.rawValue), "window": .string(request.window ?? "")])
    }
    try server.start()
    defer { server.stop() }
    let windows = await withTaskGroup(of: String?.self) { group in
        for index in 0..<clients {
            group.addTask {
                let answer = try? await AgentSocket.send(AgentRequest(.capture, window: "w\(index)"), to: url, timeout: .seconds(30))
                return answer?["window"]?.string
            }
        }
        var windows: [String] = []
        for await window in group {
            windows.append(window ?? "none")
        }
        return windows
    }
    #expect(Set(windows) == Set((0..<clients).map { "w\($0)" }))
    #expect(await arrivals.count == clients)
}

@Test func stoppingRemovesTheSocket() async throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    server.stop()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(await failure(AgentRequest(.status), at: url)?.exitCode == 69)
}

@Test func aPathTooLongForASocketIsAClearError() {
    let url = URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 120) + "/agent.sock")
    do {
        try echoServer(at: url).start()
        Issue.record("a \(url.path.utf8.count)-byte path was accepted")
    } catch {
        #expect(error.exitCode == 73)
        #expect(error.message.contains("a socket's path can be at most 103"))
    }
}

@Test func theSocketIsKeyedByBundleID() {
    #expect(AgentSocket.url(bundleID: "dev.lorcan.Shot.dev").path.hasSuffix("Library/Application Support/dev.lorcan.Shot.dev/agent.sock"))
    #expect(AgentSocket.url(bundleID: "dev.lorcan.Shot") != AgentSocket.url(bundleID: "dev.lorcan.Shot.dev"))
}

@Test func hangingUpCancelsTheAppsAnswer() async throws {
    let url = try socketURL()
    let started = Mutex(false), cancelled = Mutex(false)
    let server = AgentSocket.Server(url: url) { _ in
        started.withLock { $0 = true }
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            cancelled.withLock { $0 = true }
        }
        return .success([:])
    }
    try server.start()
    defer { server.stop() }
    let waiting = Task { await failure(AgentRequest(.waitForSend, duration: 30), at: url, timeout: .seconds(40)) }
    // Hang up only once the app is answering, as an agent that stops waiting does.
    for _ in 0 ..< 500 where !started.withLock({ $0 }) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(started.withLock { $0 })
    waiting.cancel()
    _ = await waiting.value
    for _ in 0 ..< 500 where !cancelled.withLock({ $0 }) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cancelled.withLock { $0 })
}

@Test func aWaitForASendNeedsNoCaptureSettingAndRoundTrips() throws {
    #expect(!AgentRequest.Operation.waitForSend.needsAgentCapture)
    let decoded = try AgentRequest.decode(AgentRequest(.waitForSend, duration: 60).line.dropLast())
    #expect(decoded.op == .waitForSend && decoded.duration == 60)
    let record = CaptureRecord(kind: "image", created: Date(timeIntervalSince1970: 0), size: .init(width: 10, height: 10), scale: 2)
    let sent = AgentSent(path: "/shots/Shot.png", prompt: "Fix it", record: record)
    #expect(AgentSent(fields: sent.fields) == sent)
    #expect(AgentSent(fields: ["path": .string("/a.png")]) == nil)
}
