import Foundation
import Testing
@testable import ShotCore

@Test func hotkeyEncodeDecodeRoundTrip() {
    for combo in ShotAction.allCases.compactMap(\.defaultCombo) {
        #expect(KeyCombo(encoded: combo.encoded) == combo)
    }
    let custom = KeyCombo(keyCode: 122, modifiers: KeyCombo.control | KeyCombo.option)
    #expect(KeyCombo(encoded: custom.encoded) == custom)
    #expect(custom.displayString == "⌃⌥F1")
    #expect(KeyCombo(encoded: "") == nil)
    #expect(KeyCombo(encoded: "x:1") == nil)
}

@Test func defaultHotkeysMatchPlan() {
    #expect(ShotAction.captureArea.defaultCombo?.displayString == "⌃⇧4")
    #expect(ShotAction.captureFullscreen.defaultCombo?.displayString == "⌃⇧3")
    #expect(ShotAction.captureWindow.defaultCombo?.displayString == "⌃⇧W")
    #expect(ShotAction.record.defaultCombo?.displayString == "⌃⇧5")
    #expect(ShotAction.recordFullscreen.defaultCombo == nil)
    #expect(ShotAction.recordWindow.defaultCombo == nil)
    let defaults = ShotAction.allCases.compactMap(\.defaultCombo)
    #expect(Set(defaults).count == defaults.count)
    // Two modifiers at most, and never ⌘, so no default can hit the macOS screenshot keys.
    for combo in defaults {
        #expect(combo.modifiers == KeyCombo.control | KeyCombo.shift)
    }
    #expect(ShotAction.allCases.filter(\.isRecording) == [.record, .recordFullscreen, .recordWindow])
}

@Test func replacementHotkeysTakeTheMacOSKeys() {
    let replaced = ShotAction.allCases.map { $0.defaultCombo(replacingSystemScreenshots: true)?.displayString }
    #expect(replaced == ["⇧⌘4", "⇧⌘3", nil, "⇧⌘5", nil, nil])
    #expect(ShotAction.allCases.allSatisfy { $0.defaultCombo(replacingSystemScreenshots: false) == $0.defaultCombo })
}

/// Registered defaults are shared by the whole process, so tests that register them run one at a time.
@Suite(.serialized) struct RegisteredDefaultsTests {
    @Test func registeringDefaultsFollowsReplacementButKeepsCustomShortcuts() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        #expect(prefs.hotkey(for: .record)?.displayString == "⇧⌘5")
        let custom = KeyCombo(keyCode: 122, modifiers: KeyCombo.control | KeyCombo.option)
        store.set(custom.encoded, forKey: PreferenceKey.hotkey(.captureFullscreen))
        store.set(false, forKey: PreferenceKey.replacesSystemScreenshots)
        Preferences.registerDefaults(in: store)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⌃⇧4")
        #expect(prefs.hotkey(for: .captureFullscreen) == custom)
        store.set(true, forKey: PreferenceKey.replacesSystemScreenshots)
        Preferences.registerDefaults(in: store)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        #expect(prefs.hotkey(for: .captureFullscreen) == custom)
    }

    @Test func preferenceDefaults() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        #expect(prefs.saveFolder.path.hasSuffix("/Pictures/Shot"))
        #expect(prefs.playSound)
        #expect(prefs.filePrefix == "Shot")
        #expect(prefs.imageFormat == .png)
        #expect(!prefs.downscaleRetina)
        #expect(!prefs.openEditorAfterCapture)
        #expect(!prefs.captureShowsCursor)
        #expect(prefs.hidesShotUI)
        #expect(!prefs.excludesMenuBar)
        #expect(prefs.showMagnifier)
        #expect(prefs.showCrosshair)
        #expect(prefs.quickAccessPosition == .left)
        #expect(!prefs.recordSystemAudio)
        #expect(prefs.showRecordingBorder)
        #expect(prefs.copyAfterRecording)
        #expect(!prefs.recordCamera)
        #expect(prefs.cameraDeviceID.isEmpty)
        #expect(prefs.microphoneDeviceID.isEmpty)
        #expect(prefs.cameraSize == .medium)
        #expect(prefs.saveAfterCapture)
        #expect(prefs.copyAfterCapture)
        #expect(prefs.quickAccessAfterCapture)
        #expect(prefs.quickAccessDuration == 8)
        #expect(prefs.windowShadow)
        #expect(prefs.recordingFPS == 60)
        #expect(!prefs.recordMicrophone)
        #expect(prefs.recordShowsCursor)
        #expect(prefs.replacesSystemScreenshots)
        #expect(prefs.videoExportOptions == VideoExportOptions())
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        store.set("", forKey: PreferenceKey.hotkey(.record))
        #expect(prefs.hotkey(for: .record) == nil)
    }

    @Test func resetAndPrefixSanitizing() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        store.set("  ", forKey: PreferenceKey.filePrefix)
        #expect(prefs.filePrefix == "Shot")
        store.set("a/b", forKey: PreferenceKey.filePrefix)
        #expect(prefs.filePrefix == "a-b")
        store.set("", forKey: PreferenceKey.hotkey(.captureArea))
        store.set(false, forKey: PreferenceKey.playSound)
        Preferences.resetHotkeys(in: store)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        #expect(!prefs.playSound)
        store.set(true, forKey: PreferenceKey.disabledSystemScreenshots)
        Preferences.resetAll(in: store)
        #expect(prefs.playSound)
        #expect(prefs.disabledSystemScreenshots)
        #expect(prefs.filePrefix == "Shot")
    }

    @Test func exportOptionsRememberFormatAndGIFSettingsOnly() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        Preferences.remember(VideoExportOptions(format: .gif, gifFrameRate: 24, gifWidth: VideoExportOptions.originalWidth, muted: true, speed: 2), in: store)
        #expect(prefs.videoExportOptions == VideoExportOptions(format: .gif, gifFrameRate: 24, gifWidth: VideoExportOptions.originalWidth))
        // Values Shot doesn't offer fall back to the defaults.
        store.set(12, forKey: PreferenceKey.gifFrameRate)
        store.set(333, forKey: PreferenceKey.gifWidth)
        store.set("webm", forKey: PreferenceKey.videoExportFormat)
        #expect(prefs.videoExportOptions == VideoExportOptions())
        Preferences.remember(VideoExportOptions(format: .gif), in: store)
        Preferences.resetAll(in: store)
        #expect(prefs.videoExportOptions == VideoExportOptions())
    }

    @Test func editorStyleStartsWithArrowFirstColourAndMiddleWidth() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let style = Preferences(store: store).editorStyle
        #expect(style == EditorStyle())
        #expect(style.tool == .arrow)
        #expect(style.color == RGBA.presets[0])
        #expect(style.noteColor == RGBA.presets[2])
        #expect(style.fill == nil)
        #expect(style.widthIndex == 1)
    }

    @Test func editorStyleRemembersToolColoursAndWidth() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        // The Done-when case: the star shape, blue and the thick width carry over to the next editor.
        let blue = RGBA(0, 0.48, 1)
        let thick = try #require(EditorStyle.widths.indices.last)
        let custom = RGBA(0.2, 0.4, 0.6, 0.5)
        let style = EditorStyle(
            tool: .shape, color: blue, noteColor: RGBA.presets[3], fill: custom, widthIndex: thick, recentColors: [custom],
            shape: .star, redaction: .pixelate, spotlight: SpotlightStyle(shape: .ellipse, effect: .blur, strength: .strong)
        )
        Preferences.remember(style, in: store)
        #expect(prefs.editorStyle == style)
        Preferences.resetAll(in: store)
        #expect(prefs.editorStyle == EditorStyle())
    }

    @Test func selectAndCropAreNeverTheStartingTool() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        Preferences.remember(EditorStyle(tool: .pen), in: store)
        for tool in [EditorTool.select, .crop] {
            Preferences.remember(EditorStyle(tool: tool, color: RGBA.presets[4]), in: store)
            #expect(prefs.editorStyle.tool == .pen)
            #expect(prefs.editorStyle.color == RGBA.presets[4])
        }
        #expect(EditorTool.allCases.filter { !$0.isDrawing } == [.select, .crop])
        // Even if a stored value says otherwise.
        store.set(EditorTool.crop.rawValue, forKey: PreferenceKey.editorTool)
        #expect(prefs.editorStyle.tool == .arrow)
    }

    @Test func editorStyleIgnoresValuesShotDoesNotOffer() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        // From an older or newer Shot: a tool it doesn't have, and indexes past the palette and widths.
        // Colours older versions saved are palette indexes.
        store.set("lasso", forKey: PreferenceKey.editorTool)
        store.set(RGBA.presets.count, forKey: PreferenceKey.editorColor)
        store.set(-1, forKey: PreferenceKey.editorNoteColor)
        store.set(EditorStyle.widths.count, forKey: PreferenceKey.editorWidth)
        #expect(prefs.editorStyle == EditorStyle())
        store.set("thick", forKey: PreferenceKey.editorWidth)
        #expect(prefs.editorStyle.widthIndex == EditorStyle().widthIndex)
        // Each value falls back on its own, so one bad value keeps the rest.
        store.set(EditorTool.text.rawValue, forKey: PreferenceKey.editorTool)
        store.set(5, forKey: PreferenceKey.editorColor)
        #expect(prefs.editorStyle == EditorStyle(tool: .text, color: RGBA.presets[5]))
    }

    @Test func toolsFromOlderVersionsBecomeTheToolsThatReplacedThem() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        for (old, tool) in [("rect", EditorTool.shape), ("ellipse", .shape), ("pixelate", .redact), ("blur", .redact)] {
            store.set(old, forKey: PreferenceKey.editorTool)
            #expect(prefs.editorStyle.tool == tool)
        }
    }

    @Test func removingTextCaptureDeletesItsShortcut() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        store.set("17:4608", forKey: "hotkey.capture-text")
        store.set("", forKey: PreferenceKey.hotkey(.record))
        Preferences.removeTextCapture(in: store)
        #expect(store.object(forKey: "hotkey.capture-text") == nil)
        #expect(store.string(forKey: PreferenceKey.hotkey(.record)) == "")
        #expect(ShotAction(rawValue: "capture-text") == nil)
    }
}
