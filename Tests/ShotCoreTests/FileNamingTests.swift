import Foundation
import Testing
@testable import ShotCore

private let date: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 10; components.day = 2
    components.hour = 14; components.minute = 3; components.second = 11
    return Calendar.current.date(from: components)!
}()

@Test func baseNameFormat() {
    #expect(FileNaming.baseName(for: date) == "Shot 2026-10-02 at 14.03.11")
}

@Test func uniqueURLAddsCollisionSuffixes() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    let taken: Set<String> = ["Shot 2026-10-02 at 14.03.11.png", "Shot 2026-10-02 at 14.03.11 (2).png"]
    let url = FileNaming.uniqueURL(in: folder, date: date, pathExtension: "png") { taken.contains($0.lastPathComponent) }
    #expect(url.lastPathComponent == "Shot 2026-10-02 at 14.03.11 (3).png")
    let free = FileNaming.uniqueURL(in: folder, date: date, pathExtension: "mp4") { _ in false }
    #expect(free.lastPathComponent == "Shot 2026-10-02 at 14.03.11.mp4")
}
