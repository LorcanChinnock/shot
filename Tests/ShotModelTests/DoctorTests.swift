import Foundation
import Testing
@testable import ShotModel

/// A copy of Shot where everything works.
private func healthy() -> Doctor.Facts {
    Doctor.Facts(
        bundleID: "dev.lorcan.Shot", appPath: "/Applications/Shot.app", version: "0.7.0", settingsSuite: "dev.lorcan.Shot.dev",
        agentCapture: true, socketPath: "/agent.sock", listening: true,
        status: .success(["capturing": .bool(false), "screenRecording": .bool(true), "version": .string("0.7.0")]),
        folder: "/Users/me/Pictures/Shot", folderExists: true, folderError: nil, captures: 12
    )
}

private func outcomes(_ facts: Doctor.Facts) -> [String: Doctor.Outcome] {
    Dictionary(uniqueKeysWithValues: Doctor.checks(facts).map { ($0.name, $0.outcome) })
}

private func check(_ name: String, _ facts: Doctor.Facts) -> Doctor.Check? {
    Doctor.checks(facts).first { $0.name == name }
}

@Test func aHealthyCopyPassesEveryCheck() {
    let checks = Doctor.checks(healthy())
    #expect(checks.map(\.name) == ["app", "letAgentsCaptureAndRecord", "socket", "screenRecording", "captureFolder"])
    #expect(checks.allSatisfy { $0.outcome == .pass && $0.fix == nil })
    #expect(checks[0].detail == "Shot 0.7.0 (dev.lorcan.Shot) at /Applications/Shot.app answers this command.")
    #expect(checks[4].detail == "/Users/me/Pictures/Shot can be read and holds 12 captures.")
    #expect(Doctor.json(checks)["ok"] == .bool(true))
}

@Test func theAppSaysWhichCopyAndWarnsWhenTheRunningOneDiffers() {
    var facts = healthy()
    facts.bundleID = "dev.lorcan.Shot.dev"
    facts.version = "dev"
    facts.status = .success(["screenRecording": .bool(true), "version": .string("dev")])
    #expect(check("app", facts)?.detail.hasPrefix("ShotDev dev (dev.lorcan.Shot.dev)") == true)
    facts = healthy()
    facts.status = .success(["screenRecording": .bool(true), "version": .string("0.6.9")])
    let stale = check("app", facts)
    #expect(stale?.outcome == .warn)
    #expect(stale?.detail.hasSuffix("The copy that's running is 0.6.9.") == true)
    #expect(stale?.fix == "Quit Shot and open it again, so the running copy matches this command.")
    facts.bundleID = nil
    #expect(check("app", facts)?.outcome == .warn)
    #expect(check("app", facts)?.detail.contains("reads the dev.lorcan.Shot.dev settings and asks ShotDev") == true)
}

@Test func withTheSettingOffTheSocketAndPermissionCantBeChecked() {
    var facts = healthy()
    facts.agentCapture = false
    facts.listening = false
    facts.status = nil
    #expect(outcomes(facts) == ["app": .pass, "letAgentsCaptureAndRecord": .warn, "socket": .unknown, "screenRecording": .unknown, "captureFolder": .pass])
    #expect(check("letAgentsCaptureAndRecord", facts)?.fix?.hasPrefix("Turn on Settings › Agents › Let agents capture and record in Shot") == true)
    // Only a failure makes the whole run fail: an agent can still read captures.
    #expect(Doctor.json(Doctor.checks(facts))["ok"] == .bool(true))
}

@Test func nothingListeningFailsTheSocketAndSaysToOpenShot() {
    var facts = healthy()
    facts.listening = false
    facts.status = nil
    let socket = check("socket", facts)
    #expect(socket?.outcome == .fail)
    #expect(socket?.detail == "Nothing answers at /agent.sock.")
    #expect(socket?.fix?.hasPrefix("Open Shot") == true)
    #expect(check("screenRecording", facts)?.outcome == .unknown)
    #expect(Doctor.json(Doctor.checks(facts))["ok"] == .bool(false))
    facts.listening = true
    facts.status = .failure(.unavailable("Shot didn't answer within 5 seconds."))
    #expect(check("socket", facts)?.detail == "Shot is listening at /agent.sock but didn't answer: Shot didn't answer within 5 seconds.")
}

@Test func thePermissionComesFromTheAppsStatus() {
    var facts = healthy()
    facts.status = .success(["screenRecording": .bool(false)])
    let missing = check("screenRecording", facts)
    #expect(missing?.outcome == .fail)
    #expect(missing?.fix == "Turn on Shot in System Settings › Privacy & Security › Screen & System Audio Recording, then quit Shot and open it again.")
    facts.status = .success(["capturing": .bool(false)])
    #expect(check("screenRecording", facts)?.outcome == .unknown)
    #expect(check("screenRecording", facts)?.fix == "Update Shot, so it matches this command.")
}

@Test func theFolderMustExistAndBeReadable() {
    var facts = healthy()
    facts.captures = 1
    #expect(check("captureFolder", facts)?.detail.hasSuffix("holds 1 capture.") == true)
    facts.folderError = "Operation not permitted"
    let blocked = check("captureFolder", facts)
    #expect(blocked?.outcome == .fail)
    #expect(blocked?.detail == "macOS doesn't let this process read /Users/me/Pictures/Shot: Operation not permitted")
    #expect(blocked?.fix?.contains("Privacy & Security › Files and Folders") == true)
    facts.folderExists = false
    #expect(check("captureFolder", facts)?.outcome == .warn)
}

@Test func theJSONGivesEachCheckAndOnlyFixesThatApply() {
    var facts = healthy()
    facts.folderExists = false
    guard case let .array(checks)? = Doctor.json(Doctor.checks(facts))["checks"] else {
        Issue.record("no checks")
        return
    }
    #expect(checks[0] == .object(["name": .string("app"), "outcome": .string("pass"), "detail": .string("Shot 0.7.0 (dev.lorcan.Shot) at /Applications/Shot.app answers this command.")]))
    #expect(checks[4]["outcome"] == .string("warn"))
    #expect(checks[4]["fix"] != nil)
}
