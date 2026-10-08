import Testing
@testable import ShotCore

@Test func dropsLeastRecentlyUsedOverLimit() {
    var recent = RecentlyUsed<String>(limit: 10)
    #expect(recent.use("a", cost: 4).isEmpty)
    #expect(recent.use("b", cost: 4).isEmpty)
    #expect(recent.use("a", cost: 4).isEmpty, "using a key again doesn't add its cost twice")
    #expect(recent.total == 8)
    #expect(recent.use("c", cost: 4) == ["b"])
    #expect(recent.use("d", cost: 8) == ["a", "c"])
    #expect(recent.total == 8)
}

@Test func keepsJustUsedKeyEvenOverLimit() {
    var recent = RecentlyUsed<String>(limit: 10)
    _ = recent.use("a", cost: 3)
    #expect(recent.use("big", cost: 25) == ["a"])
    #expect(recent.total == 25)
    #expect(!recent.isEmpty)
}

@Test func removeAllEmpties() {
    var recent = RecentlyUsed<String>(limit: 10)
    _ = recent.use("a", cost: 3)
    recent.removeAll()
    #expect(recent.isEmpty)
    #expect(recent.total == 0)
    #expect(recent.use("a", cost: 3).isEmpty)
    #expect(recent.total == 3)
}
