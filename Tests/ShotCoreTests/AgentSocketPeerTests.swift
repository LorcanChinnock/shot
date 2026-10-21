import Foundation
import Testing
@testable import ShotCore

// The parts of the agent socket that differ between Darwin and Glibc. AgentSocketTests, on a Mac, covers the rest.

@Test func agentSocketReadsItsPeersUser() {
    var fds: [Int32] = [-1, -1]
    #expect(socketpair(AF_UNIX, AgentSocket.stream, 0, &fds) == 0)
    defer {
        close(fds[0])
        close(fds[1])
    }
    #expect(AgentSocket.peerUser(of: fds[0]) == getuid())
    #expect(AgentSocket.peerUser(of: -1) == nil)
}

@Test func agentSocketAnswersARequestFromThisUser() async throws {
    // A short folder of its own, since a socket's whole path must fit in 103 bytes.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ap-\(UUID().uuidString.prefix(8))")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("agent.sock")
    let server = AgentSocket.Server(url: url) { request in
        .success(["op": .string(request.op.rawValue)])
    }
    try server.start()
    defer { server.stop() }
    let answer = try await AgentSocket.send(AgentRequest(.status), to: url, timeout: .seconds(5))
    #expect(answer["op"] == .string("status"))
}

@Test func agentSocketAnswersOnAQueueOfItsOwnRatherThanThePool() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ap-\(UUID().uuidString.prefix(8))")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("agent.sock")
    // So an answer never waits for work holding every thread of the pool, as tests drawing in parallel do.
    let server = AgentSocket.Server(url: url) { _ in
        .success(["answering": .bool(DispatchQueue.getSpecific(key: AgentSocket.answering) == true)])
    }
    try server.start()
    defer { server.stop() }
    let answer = try await AgentSocket.send(AgentRequest(.status), to: url, timeout: .seconds(5))
    #expect(answer["answering"] == .bool(true))
}
