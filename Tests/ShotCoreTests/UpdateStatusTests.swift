import Foundation
import Testing
@testable import ShotCore

@Test func updateStatusIsOffWithoutAFeed() {
    #expect(UpdateStatus(hasFeed: false, pendingVersion: "1.2", lastResult: .upToDate, lastCheck: .now) == .off)
}

@Test func updateStatusPrefersAPendingVersion() {
    #expect(UpdateStatus(hasFeed: true, pendingVersion: "1.2", lastResult: .upToDate, lastCheck: .now) == .available(version: "1.2"))
    #expect(UpdateStatus(hasFeed: true, pendingVersion: "1.2", lastResult: nil, lastCheck: nil).availableVersion == "1.2")
}

@Test func updateStatusKeepsAVersionFoundThisSession() {
    // Later in Sparkle's window clears the pending version, but the update is still out there.
    #expect(UpdateStatus(hasFeed: true, pendingVersion: nil, lastResult: .found(version: "1.3"), lastCheck: .now) == .available(version: "1.3"))
}

@Test func updateStatusSaysUpToDateOnlyAfterACheckThisSession() {
    let earlier = Date(timeIntervalSince1970: 1_000_000)
    #expect(UpdateStatus(hasFeed: true, pendingVersion: nil, lastResult: .upToDate, lastCheck: earlier) == .upToDate)
    #expect(UpdateStatus(hasFeed: true, pendingVersion: nil, lastResult: nil, lastCheck: earlier) == .lastChecked(earlier))
    #expect(UpdateStatus(hasFeed: true, pendingVersion: nil, lastResult: nil, lastCheck: nil) == .notChecked)
    #expect(UpdateStatus.upToDate.availableVersion == nil)
}
