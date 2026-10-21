import Synchronization
import Testing
@testable import ShotCore

@Test func percentProgressPassesOnEachWholePercentOnce() {
    let reported = Mutex<[Int]>([])
    let progress = PercentProgress { percent in reported.withLock { $0.append(percent) } }
    for frame in 1...900 {
        progress.report(Double(frame) / 900)
    }
    progress.report(1)
    #expect(reported.withLock { $0 } == Array(0...100))
}
