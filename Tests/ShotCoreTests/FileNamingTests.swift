import Foundation
import Testing
@testable import ShotCore

@Test func baseNameFormat() {
    var components = DateComponents()
    components.year = 2026; components.month = 10; components.day = 2
    components.hour = 14; components.minute = 3; components.second = 11
    let date = Calendar.current.date(from: components)!
    #expect(FileNaming.baseName(for: date) == "Shot 2026-10-02 at 14.03.11")
}
