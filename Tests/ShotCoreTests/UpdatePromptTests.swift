import Foundation
import Testing
@testable import ShotCore

private func offer(stage: UpdateOffer.Stage = .notDownloaded, critical: Bool = false, major: Bool = false, infoOnly: Bool = false) -> UpdateOffer {
    UpdateOffer(version: "0.8.0", build: "700", installedVersion: "0.7.0", installedBuild: "667", stage: stage, isCritical: critical, isMajorUpgrade: major, isInformationOnly: infoOnly)
}

@Test func updatePromptOffersSkipLaterAndInstall() {
    let buttons = UpdatePromptButtons(offer: offer(), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(buttons.install == .installAndRelaunch)
    #expect(buttons.later == .later)
    #expect(buttons.showsSkip)
    #expect(buttons.showsAutomaticInstall)
}

@Test func updatePromptHidesLaterWithoutAutomaticChecks() {
    // Later means "at the next check", and there isn't one.
    let buttons = UpdatePromptButtons(offer: offer(), automaticallyChecks: false, allowsAutomaticUpdates: false)
    #expect(buttons.later == .hidden)
    #expect(buttons.showsSkip)
    #expect(!buttons.showsAutomaticInstall)
}

@Test func updatePromptInstallsOnQuitOnceUnpacked() {
    #expect(UpdatePromptButtons(offer: offer(stage: .installing), automaticallyChecks: true, allowsAutomaticUpdates: true).later == .installOnQuit)
    #expect(UpdatePromptButtons(offer: offer(stage: .downloaded), automaticallyChecks: true, allowsAutomaticUpdates: true).later == .later)
}

@Test func updatePromptCriticalUpdateCantBePutOff() {
    let critical = UpdatePromptButtons(offer: offer(critical: true), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(!critical.showsSkip)
    #expect(critical.later == .hidden)
    // A critical major upgrade can still be skipped, as in Sparkle.
    let major = UpdatePromptButtons(offer: offer(critical: true, major: true), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(major.showsSkip)
    #expect(major.later == .later)
}

@Test func updatePromptInformationOnlyOpensThePage() {
    let buttons = UpdatePromptButtons(offer: offer(infoOnly: true), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(buttons.install == .learnMore)
    #expect(!buttons.showsAutomaticInstall)
}

@Test func updateOfferVersionsAddBuildsWhenTheyMatch() {
    #expect(offer().versions == ("0.8.0", "0.7.0"))
    let same = UpdateOffer(version: "0.7.0", build: "700", installedVersion: "0.7.0", installedBuild: "667")
    #expect(same.versions == ("0.7.0 (700)", "0.7.0 (667)"))
}

@Test func updateDownloadProgressCountsBytes() {
    var progress = UpdateDownloadProgress()
    #expect(progress.fraction == nil)
    progress.expect(1000)
    progress.receive(250)
    progress.receive(250)
    #expect(progress.fraction == 0.5)
    progress.receive(900)
    #expect(progress.fraction == 1)
    let sizes = progress.sizes { "\($0)" }
    #expect(sizes.received == "1400")
    #expect(sizes.total == "1400")
}

@Test func updateDownloadProgressWithoutASize() {
    var progress = UpdateDownloadProgress()
    progress.expect(0)
    progress.receive(10)
    #expect(progress.fraction == nil)
    #expect(progress.sizes { "\($0)" }.total == nil)
}

@Test func releaseHighlightsReadReleasePleaseNotes() {
    let notes = """
    ## [0.7.0-beta.83](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.82...v0.7.0-beta.83) (2026-11-05)


    ### Bug Fixes

    * **editor:** click edits and drag moves text and notes under their own tool ([#1146](https://github.com/LorcanChinnock/shot/issues/1146)) ([b0e7b95](https://github.com/LorcanChinnock/shot/commit/b0e7b95b1437c3c2643108d46db21d3ad129dfc5))
    * **gallery:** let the main window shrink and keep tiles one size ([#1144](https://github.com/LorcanChinnock/shot/issues/1144)) ([dae394a](https://github.com/LorcanChinnock/shot/commit/dae394a))
    * keep `Copy Path` working ([#1](https://example.com/1))
    """
    #expect(ReleaseHighlights.parse(notes, format: .markdown) == [
        "Click edits and drag moves text and notes under their own tool",
        "Let the main window shrink and keep tiles one size",
        "Keep Copy Path working",
    ])
}

@Test func releaseHighlightsReadHTMLLists() {
    let notes = "<h2>New</h2><ul><li>Blur hides <b>emails</b> &amp; names</li>\n<li class=\"x\">Faster GIFs</li></ul><p>Thanks!</p>"
    #expect(ReleaseHighlights.parse(notes, format: .html) == ["Blur hides emails & names", "Faster GIFs"])
}

@Test func releaseHighlightsNeedAList() {
    #expect(ReleaseHighlights.parse("Just a paragraph about the release.", format: .plainText).isEmpty)
    #expect(ReleaseHighlights.parse("- one\n-\n• two", format: .plainText) == ["One", "Two"])
}

@Test func releaseHighlightsFormatFromFile() {
    #expect(ReleaseHighlights.format(mimeType: "text/markdown", pathExtension: nil) == .markdown)
    #expect(ReleaseHighlights.format(mimeType: nil, pathExtension: "md") == .markdown)
    #expect(ReleaseHighlights.format(mimeType: "text/plain", pathExtension: "html") == .plainText)
    #expect(ReleaseHighlights.format(mimeType: "text/html", pathExtension: "html") == .html)
}
