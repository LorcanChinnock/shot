import Foundation
import os
import ShotCore

private let log = Logger.shot("agents")

/// Answers agents on the app's socket while Let agents capture and record is on, so `shot capture` and the MCP server can
/// ask for a screenshot that only the app, with its Screen Recording permission, can take.
@MainActor
final class AgentServer {
    static let shared = AgentServer()

    weak var coordinator: CaptureCoordinator?
    private var server: AgentSocket.Server?

    private init() {}

    /// Starts or stops listening to match the setting. Cheap when nothing changed, so it can run on every defaults change.
    func update() {
        let enabled = Preferences().agentCapture
        guard enabled != (server != nil) else {
            return
        }
        guard enabled else {
            server?.stop()
            server = nil
            log.notice("Stopped answering agents")
            return
        }
        let url = AgentSocket.url(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot.dev")
        let server = AgentSocket.Server(url: url) { request in
            await AgentServer.shared.handle(request)
        }
        do {
            try server.start()
        } catch {
            log.error("Couldn't answer agents: \(error.message, privacy: .public)")
            Toast.error("Agents can't reach Shot: \(error.message)")
            return
        }
        self.server = server
        log.notice("Answering agents at \(url.path, privacy: .public)")
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private func handle(_ request: AgentRequest) async -> AgentResponse {
        log.notice("Agent request: \(request.op.rawValue, privacy: .public)")
        // The setting can go off between the request arriving and here.
        guard server != nil, let coordinator else {
            return .failure(.unavailable(AgentSocket.turnedOff))
        }
        switch request.op {
        case .capture:
            do {
                return .success(try await coordinator.agentCapture(window: request.window ?? ""))
            } catch {
                return .failure(error)
            }
        case .status:
            return .success(coordinator.agentStatus())
        }
    }
}
