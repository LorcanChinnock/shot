import Foundation
import Synchronization
import Testing
@testable import ShotModel

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func entry(_ name: String, secondsAgo: Double = 0, bytes: Int? = nil) -> AgentCaptures.Entry {
    AgentCaptures.Entry(url: URL(fileURLWithPath: "/shots/\(name)"), isVideo: name.hasSuffix(".mp4"), date: now.addingTimeInterval(-secondsAgo), bytes: bytes)
}

@Test func whatTheFolderHeldAtTheStartIsNeverNew() {
    let before = [entry("Shot A.png", secondsAgo: 60), entry("Recording B.mp4", secondsAgo: 30)]
    var watch = CaptureWatch(before)
    #expect(watch.arrivals(in: before).isEmpty)
}

@Test func eachNewCaptureArrivesOnceOldestFirst() {
    let before = [entry("Shot A.png", secondsAgo: 60)]
    var watch = CaptureWatch(before)
    let later = before + [entry("Shot C.png", secondsAgo: 1), entry("Shot B.png", secondsAgo: 2)]
    #expect(watch.arrivals(in: later).map(\.name) == ["Shot B.png", "Shot C.png"])
    #expect(watch.arrivals(in: later).isEmpty)
}

@Test func aFileStillGrowingWaitsUntilItsSizeHolds() {
    var watch = CaptureWatch([])
    #expect(watch.arrivals(in: [entry("Recording A.mp4", bytes: 1000)]).isEmpty)
    #expect(watch.arrivals(in: [entry("Recording A.mp4", bytes: 5000)]).isEmpty)
    #expect(watch.arrivals(in: [entry("Recording A.mp4", bytes: 5000)]).map(\.name) == ["Recording A.mp4"])
}

@Test func anEmptyFileNeverArrives() {
    var watch = CaptureWatch([])
    #expect(watch.arrivals(in: [entry("Shot A.png", bytes: 0)]).isEmpty)
    #expect(watch.arrivals(in: [entry("Shot A.png", bytes: 0)]).isEmpty)
}

@Test func onlyTheKindAskedForArrives() {
    var watch = CaptureWatch([], kind: .video)
    #expect(watch.arrivals(in: [entry("Shot A.png"), entry("Recording B.mp4")]).map(\.name) == ["Recording B.mp4"])
}

@Test func aScreenshotSavedAgainFromTheEditorArrivesAsItsNewVersion() {
    let before = [entry("Shot A.png", secondsAgo: 60)]
    var watch = CaptureWatch(before)
    #expect(watch.arrivals(in: before + [entry("Shot A (2).png")]).map(\.name) == ["Shot A (2).png"])
}

@Test func anOlderVersionShownAgainAfterTheNewerIsDeletedIsntNew() {
    let before = [entry("Shot A.png", secondsAgo: 60), entry("Shot A (2).png", secondsAgo: 30)]
    var watch = CaptureWatch(before)
    #expect(watch.arrivals(in: [entry("Shot A.png", secondsAgo: 60)]).isEmpty)
}

@Test func nextReturnsTheFirstCaptureToArrive() async {
    let folder = Mutex([entry("Shot A.png", secondsAgo: 60)])
    let task = Task {
        await CaptureWatch.next(timeout: 5, interval: .milliseconds(10)) { folder.withLock { $0 } }
    }
    try? await Task.sleep(for: .milliseconds(50))
    folder.withLock { $0.append(entry("Shot B.png")) }
    #expect(await task.value?.name == "Shot B.png")
}

@Test func nextGivesNothingWhenTheTimeoutPasses() async {
    let clock = ContinuousClock()
    let start = clock.now
    let found = await CaptureWatch.next(timeout: 0.1, interval: .milliseconds(10)) { [entry("Shot A.png")] }
    #expect(found == nil)
    #expect(clock.now - start < .seconds(2))
}

@Test func watchHandsOverEachCaptureUntilToldToStop() async {
    let folder = Mutex<[AgentCaptures.Entry]>([])
    let seen = Mutex<[String]>([])
    let task = Task {
        await CaptureWatch.watch(timeout: 5, interval: .milliseconds(10), entries: { folder.withLock { $0 } }) { entry in
            seen.withLock { $0.append(entry.name) }
            return seen.withLock { $0.count } < 2
        }
    }
    for name in ["Shot A.png", "Shot B.png", "Shot C.png"] {
        try? await Task.sleep(for: .milliseconds(50))
        folder.withLock { $0.append(entry(name)) }
    }
    await task.value
    #expect(seen.withLock { $0 } == ["Shot A.png", "Shot B.png"])
}

@Test func watchStopsWhenCancelled() async {
    let task = Task {
        await CaptureWatch.watch(timeout: nil, interval: .milliseconds(10), entries: { [] }) { _ in true }
    }
    task.cancel()
    await task.value
}
