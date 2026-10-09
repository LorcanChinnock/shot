import Foundation
import Testing
@testable import ShotCore

struct AfterCaptureRow: Sendable, CustomTestStringConvertible {
    let copy, save, quickAccess, openEditor: Bool
    let image: AfterCapture
    let video: AfterCapture

    var testDescription: String { "copy \(copy), save \(save), Quick Access \(quickAccess), editor \(openEditor)" }
}

private let copied = AfterCapture.Next.toast("Copied to clipboard")
private let saved = AfterCapture.Next.toast("Saved")

private let rows: [AfterCaptureRow] = [
    AfterCaptureRow(copy: false, save: false, quickAccess: false, openEditor: false,
        image: AfterCapture(copies: false, writesFile: false, next: .nothing), video: AfterCapture(copies: false, writesFile: false, next: .nothing)),
    AfterCaptureRow(copy: true, save: false, quickAccess: false, openEditor: false,
        image: AfterCapture(copies: true, writesFile: false, next: copied), video: AfterCapture(copies: true, writesFile: false, next: copied)),
    AfterCaptureRow(copy: false, save: true, quickAccess: false, openEditor: false,
        image: AfterCapture(copies: false, writesFile: true, next: saved), video: AfterCapture(copies: false, writesFile: false, next: saved)),
    AfterCaptureRow(copy: true, save: true, quickAccess: false, openEditor: false,
        image: AfterCapture(copies: true, writesFile: true, next: copied), video: AfterCapture(copies: true, writesFile: false, next: copied)),
    AfterCaptureRow(copy: true, save: false, quickAccess: true, openEditor: false,
        image: AfterCapture(copies: true, writesFile: true, next: .quickAccess), video: AfterCapture(copies: true, writesFile: false, next: .quickAccess)),
    AfterCaptureRow(copy: false, save: false, quickAccess: false, openEditor: true,
        image: AfterCapture(copies: false, writesFile: true, next: .editor), video: AfterCapture(copies: false, writesFile: false, next: .nothing)),
    AfterCaptureRow(copy: true, save: true, quickAccess: true, openEditor: true,
        image: AfterCapture(copies: true, writesFile: true, next: .editor), video: AfterCapture(copies: true, writesFile: false, next: .quickAccess)),
    AfterCaptureRow(copy: false, save: true, quickAccess: false, openEditor: true,
        image: AfterCapture(copies: false, writesFile: true, next: .editor), video: AfterCapture(copies: false, writesFile: false, next: saved)),
]

@Test(arguments: rows)
func afterCaptureFollowsTheSettings(_ row: AfterCaptureRow) {
    #expect(AfterCapture.plan(copy: row.copy, save: row.save, quickAccess: row.quickAccess, openEditor: row.openEditor, isVideo: false) == row.image)
    #expect(AfterCapture.plan(copy: row.copy, save: row.save, quickAccess: row.quickAccess, openEditor: row.openEditor, isVideo: true) == row.video)
}

@Test func recordingsUseTheirOwnCopySetting() throws {
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    store.set(true, forKey: PreferenceKey.copyAfterCapture)
    store.set(false, forKey: PreferenceKey.copyAfterRecording)
    store.set(false, forKey: PreferenceKey.quickAccessAfterCapture)
    store.set(false, forKey: PreferenceKey.openEditorAfterCapture)
    store.set(false, forKey: PreferenceKey.saveAfterCapture)
    let prefs = Preferences(store: store)
    #expect(AfterCapture.plan(prefs: prefs, isVideo: false).copies)
    #expect(!AfterCapture.plan(prefs: prefs, isVideo: true).copies)
}
