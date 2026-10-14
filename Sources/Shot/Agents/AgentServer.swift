import Foundation
import os
import ShotCore

private let log = Logger.shot("agents")

/// Answers agents on the app's socket, so `shot capture`, `shot record` and the MCP server can ask for screenshots and
/// recordings that only the app, with its Screen Recording permission, can make. Those need Let agents capture and record
/// on, which is read for each request; only a pick, where the person makes the selection, is answered without it.
/// It listens while the app runs, so turning the setting on needs no restart.
@MainActor
final class AgentServer {
    static let shared = AgentServer()

    weak var coordinator: CaptureCoordinator?
    private var server: AgentSocket.Server?

    private init() {}

    /// Starts listening, once, as the app launches.
    func start() {
        guard server == nil else {
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
            // Only worth interrupting for when the person has asked for agents to capture.
            if Preferences().agentCapture {
                Toast.error("Agents can't reach Shot: \(error.message)")
            }
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
        guard server != nil, let coordinator else {
            return .failure(.unavailable("Shot is quitting."))
        }
        guard !request.op.needsAgentCapture || Preferences().agentCapture else {
            return .failure(.unavailable(AgentSocket.turnedOff))
        }
        switch request.op {
        case .capture:
            do {
                return .success(try await coordinator.agentCapture(request.target, origin: request.origin))
            } catch {
                return .failure(error)
            }
        case .record:
            do {
                return .success(try await coordinator.agentRecord(request.target, duration: request.duration, origin: request.origin))
            } catch {
                return .failure(error)
            }
        case .stop:
            do {
                return .success(try await coordinator.agentStop(id: request.id))
            } catch {
                return .failure(error)
            }
        case .status:
            return .success(coordinator.agentStatus())
        case .windows:
            do {
                return .success(try coordinator.agentWindows())
            } catch {
                return .failure(error)
            }
        case .mark:
            do {
                return .success(try coordinator.agentMark(label: request.label ?? "", id: request.id))
            } catch {
                return .failure(error)
            }
        case .pick:
            do {
                return .success(try await coordinator.agentPick(prompt: request.prompt, timeout: request.duration ?? ShotCommand.PickOptions.defaultTimeout, origin: request.origin))
            } catch {
                return .failure(error)
            }
        }
    }
}
