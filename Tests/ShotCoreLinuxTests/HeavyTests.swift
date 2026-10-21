import Foundation

/// Runs the tests that load CI's few cores for seconds one at a time: the recordings, which start ffmpeg, PipeWire and
/// GStreamer, and each of PerfTests' budgets, which they would otherwise push over. Each waits its turn, in the order it
/// asked.
actor HeavyTests {
    private static let gate = HeavyTests()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    static func oneAtATime(_ body: () async throws -> Void) async throws {
        await gate.enter()
        do {
            try await body()
        } catch {
            await gate.leave()
            throw error
        }
        await gate.leave()
    }

    private func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Lets the next one waiting go, which holds the gate from here.
    private func leave() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
