import Foundation
import Testing
@testable import ShotCore

private func shell(_ script: String) -> (String, [String]) {
    ("/bin/sh", ["-c", script])
}

@Test func aSubprocessHandsBackWhatItPrinted() async throws {
    let (program, arguments) = shell("printf 'hello'; printf 'ignored' >&2")
    let output = try await Subprocess.output(program, arguments)
    #expect(String(decoding: output, as: UTF8.self) == "hello")
}

@Test func aSubprocessReadsAsMuchAsItsAskedForUntilTheEnd() async throws {
    let (program, arguments) = shell("printf abc; sleep 0.1; printf def")
    let chunks = try await Subprocess.run(program, arguments) { process in
        [await process.read(upTo: 4), await process.read(upTo: 4), await process.read(upTo: 4)]
    }
    #expect(chunks.map { String(decoding: $0, as: UTF8.self) } == ["abcd", "ef", ""])
}

@Test func aSubprocessHasNothingOnItsStandardInput() async throws {
    let (program, arguments) = shell("cat")
    #expect(try await Subprocess.output(program, arguments).isEmpty)
}

@Test func aSubprocessThatFailsSaysWhyFromItsLastLineOfErrors() async throws {
    let (program, arguments) = shell("echo first >&2; echo '  last  ' >&2; exit 3")
    await #expect(throws: Subprocess.Failure(program: "sh", status: 3, message: "last")) {
        try await Subprocess.output(program, arguments)
    }
    await #expect(throws: Subprocess.Failure(program: "sh", status: 128 + SIGKILL, message: "")) {
        try await Subprocess.output(program, ["-c", "kill -9 $$"])
    }
}

@Test func aSubprocessThatCantStartSaysSo() async throws {
    #expect(throws: Subprocess.Failure.self) {
        try Subprocess("/nowhere/ffmpeg", [])
    }
}

@Test func cancellingTheTaskStopsTheSubprocess() async throws {
    let (program, arguments) = shell("sleep 30")
    let started = ContinuousClock.now
    let task = Task {
        try await Subprocess.output(program, arguments)
    }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ContinuousClock.now - started < .seconds(10))
}

@Test func aSubprocessIsStoppedWhenWhatReadsItThrows() async throws {
    struct Enough: Error {}
    let (program, arguments) = shell("while :; do echo y; done")
    let started = ContinuousClock.now
    await #expect(throws: Enough.self) {
        try await Subprocess.run(program, arguments) { process in
            _ = await process.read(upTo: 10)
            throw Enough()
        }
    }
    #expect(ContinuousClock.now - started < .seconds(10))
}

@Test func whatASubprocessPrintsAfterItsReadIsDroppedSoItCanEnd() async throws {
    let (program, arguments) = shell("head -c 1000000 /dev/zero")
    let first = try await Subprocess.run(program, arguments) { await $0.read(upTo: 10) }
    #expect(first.count == 10)
}
