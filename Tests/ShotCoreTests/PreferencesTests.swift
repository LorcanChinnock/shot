import Foundation
import Testing
@testable import ShotCore

/// Registered defaults are shared by the whole process, so tests that register them run one at a time.
@Suite(.serialized) struct RegisteredDefaultsTests {
    @Test func registeringDefaultsFollowsReplacementButKeepsCustomShortcuts() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
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
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
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
        #expect(!prefs.adjustBeforeRecording)
        #expect(prefs.recordingCountdown == 0)
        #expect(prefs.cameraDeviceID.isEmpty)
        #expect(prefs.microphoneDeviceID.isEmpty)
        #expect(prefs.cameraSize == .medium)
        #expect(!prefs.partyModeUnlocked)
        #expect(!prefs.partyMode)
        #expect(prefs.saveAfterCapture)
        #expect(prefs.copyAfterCapture)
        #expect(prefs.quickAccessAfterCapture)
        #expect(prefs.quickAccessDuration == 8)
        #expect(prefs.windowShadow)
        #expect(prefs.recordingFPS == 60)
        #expect(!prefs.recordMicrophone)
        #expect(prefs.recordShowsCursor)
        #expect(!prefs.recordShowsClicks)
        #expect(prefs.replacesSystemScreenshots)
        #expect(prefs.videoExportOptions == VideoExportOptions())
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        store.set("", forKey: PreferenceKey.hotkey(.record))
        #expect(prefs.hotkey(for: .record) == nil)
    }

    @Test func resetAndPrefixSanitizing() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
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

    @Test func capturesGoToTheSaveFolderOnlyWhenSavingIsOn() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        store.set("/tmp/ShotSaves", forKey: PreferenceKey.saveFolder)
        #expect(prefs.captureFolder == URL(fileURLWithPath: "/tmp/ShotSaves"))
        store.set(false, forKey: PreferenceKey.saveAfterCapture)
        #expect(prefs.captureFolder == FileManager.default.temporaryDirectory.appendingPathComponent("Shot"))
    }

    @Test func exportOptionsRememberFormatAndGIFSettingsOnly() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
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
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let style = Preferences(store: store).editorStyle
        #expect(style == EditorStyle())
        #expect(style.tool == .arrow)
        #expect(style.color == RGBA.presets[0])
        #expect(style.noteColor == RGBA.presets[2])
        #expect(style.highlightColor == RGBA.presets[2])
        #expect(style.fill == nil)
        #expect(style.widthIndex == 1)
    }

    @Test func editorStyleRemembersToolColoursAndWidth() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        // The Done-when case: the star shape, blue and the thick width carry over to the next editor.
        let blue = RGBA(0, 0.48, 1)
        let thick = try #require(EditorStyle.widths.indices.last)
        let custom = RGBA(0.2, 0.4, 0.6, 0.5)
        let style = EditorStyle(
            tool: .shape, color: blue, noteColor: RGBA.presets[3], highlightColor: RGBA.presets[4], fill: custom, widthIndex: thick,
            customColors: [.stroke: custom, .note: blue, .highlight: RGBA.presets[1]],
            shape: .star, redaction: .pixelate, redactionAmount: 0.013, spotlight: SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.7),
            alignment: .center, verticalAlignment: .middle
        )
        Preferences.remember(style, in: store)
        store.set(Data(), forKey: "editorRecentColors")
        #expect(prefs.editorStyle == style)
        Preferences.resetAll(in: store)
        #expect(prefs.editorStyle == EditorStyle())
        #expect(store.object(forKey: "editorRecentColors") == nil)
    }

    @Test func changingTheEditorStyleWritesOnlyWhatChanged() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        Preferences.remember(EditorStyle(tool: .pen), in: store)
        Preferences.changeEditorStyle(in: store) { $0.color = RGBA.presets[2] }
        #expect(prefs.editorStyle.color == RGBA.presets[2])
        // Every key the change didn't touch is left as it was, here with nothing stored at all.
        store.removeObject(forKey: PreferenceKey.editorTool)
        store.removeObject(forKey: PreferenceKey.editorWidth)
        Preferences.changeEditorStyle(in: store) { $0.color = RGBA.presets[3] }
        let saved = store.persistentDomain(forName: suite.name) ?? [:]
        #expect(saved[PreferenceKey.editorTool] == nil)
        #expect(saved[PreferenceKey.editorWidth] == nil)
        #expect(prefs.editorStyle.color == RGBA.presets[3])
    }

    @Test func selectAndCropAreNeverTheStartingTool() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        Preferences.remember(EditorStyle(tool: .pen), in: store)
        for tool in [EditorTool.select, .hand, .crop] {
            Preferences.remember(EditorStyle(tool: tool, color: RGBA.presets[4]), in: store)
            #expect(prefs.editorStyle.tool == .pen)
            #expect(prefs.editorStyle.color == RGBA.presets[4])
        }
        #expect(EditorTool.allCases.filter { !$0.isDrawing } == [.select, .hand, .crop])
        // Even if a stored value says otherwise.
        store.set(EditorTool.crop.rawValue, forKey: PreferenceKey.editorTool)
        #expect(prefs.editorStyle.tool == .arrow)
    }

    @Test func editorStyleIgnoresValuesShotDoesNotOffer() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        // From an older or newer Shot: a tool it doesn't have, and indexes past the palette and widths.
        // Colours older versions saved are palette indexes.
        store.set("lasso", forKey: PreferenceKey.editorTool)
        store.set(RGBA.presets.count, forKey: PreferenceKey.editorColor)
        store.set(-1, forKey: PreferenceKey.editorNoteColor)
        store.set(EditorStyle.widths.count, forKey: PreferenceKey.editorWidth)
        store.set(1.0, forKey: PreferenceKey.editorRedactionAmount)
        #expect(prefs.editorStyle == EditorStyle())
        store.set("thick", forKey: PreferenceKey.editorWidth)
        #expect(prefs.editorStyle.widthIndex == EditorStyle().widthIndex)
        // Each value falls back on its own, so one bad value keeps the rest.
        store.set(EditorTool.text.rawValue, forKey: PreferenceKey.editorTool)
        store.set(5, forKey: PreferenceKey.editorColor)
        #expect(prefs.editorStyle == EditorStyle(tool: .text, color: RGBA.presets[5]))
    }

    @Test func toolsFromOlderVersionsBecomeTheToolsThatReplacedThem() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        for (old, tool) in [("rect", EditorTool.shape), ("ellipse", .shape), ("pixelate", .redact), ("blur", .redact)] {
            store.set(old, forKey: PreferenceKey.editorTool)
            #expect(prefs.editorStyle.tool == tool)
        }
    }

    @Test func removingTextCaptureDeletesItsShortcut() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        Preferences.registerDefaults(in: store)
        store.set("17:4608", forKey: "hotkey.capture-text")
        store.set("", forKey: PreferenceKey.hotkey(.record))
        Preferences.removeTextCapture(in: store)
        #expect(store.object(forKey: "hotkey.capture-text") == nil)
        #expect(store.string(forKey: PreferenceKey.hotkey(.record)) == "")
        #expect(ShotAction(rawValue: "capture-text") == nil)
    }

    @Test func removingTranslateTargetDeletesTheSavedLanguage() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        store.set("fr", forKey: "translateTarget")
        store.set("fr", forKey: PreferenceKey.sendToAgentPreset)
        Preferences.removeTranslateTarget(in: store)
        #expect(store.object(forKey: "translateTarget") == nil)
        #expect(store.string(forKey: PreferenceKey.sendToAgentPreset) == "fr")
    }

    @Test func menuOnlyActionsHaveNoShortcutAndTheirSavedOnesAreRemoved() throws {
        let suite = try TestDefaults()
        let store = suite.store
        defer { suite.remove() }
        let menuOnly: [ShotAction] = [.recordFullscreen, .recordWindow, .pickColor, .copyPath, .capturePrevious, .focusQuickAccess]
        #expect(ShotAction.allCases.filter { !$0.hasShortcut } == menuOnly)
        for action in menuOnly {
            store.set("17:4608", forKey: PreferenceKey.hotkey(action))
            #expect(Preferences(store: store).hotkey(for: action) == nil)
        }
        store.set("15:4608", forKey: PreferenceKey.hotkey(.record))
        Preferences.removeMenuOnlyHotkeys(in: store)
        for action in menuOnly {
            #expect((store.string(forKey: PreferenceKey.hotkey(action)) ?? "").isEmpty)
        }
        #expect(store.string(forKey: PreferenceKey.hotkey(.record)) == "15:4608")
    }
}

/// `@Setting(key)` with no default of its own takes the one `Preferences` registers, so every key a view declares that way
/// must have one. Reads the app's sources, since the views can't be built here; a `PreferenceKey` is named as its value.
@Test func everySettingKeyHasARegisteredDefault() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = root.appendingPathComponent("Sources/Shot")
    let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects ?? [])
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
    var keys: Set<String> = []
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for match in text.matches(of: /@Setting\(PreferenceKey\.(\w+)\)/) {
            keys.insert(String(match.1))
        }
    }
    #expect(keys.count > 20)
    let defaults = Preferences.defaults
    for key in keys.sorted() {
        #expect(defaults[key] != nil, Comment(rawValue: key))
    }
}

@Test func theFilePrefixIsTrimmedDefaultedAndHasNoSlash() {
    #expect(Preferences.sanitizedPrefix("  Bug report ") == "Bug report")
    #expect(Preferences.sanitizedPrefix("   ") == Preferences.defaultFilePrefix)
    #expect(Preferences.sanitizedPrefix("") == Preferences.defaultFilePrefix)
    #expect(Preferences.sanitizedPrefix("a/b") == "a-b")
}

@Test func resettingSettingsAlsoResetsTheWindowLayout() throws {
    let suite = try TestDefaults()
    let store = suite.store
    defer { suite.remove() }
    for key in [PreferenceKey.editorShowsLayers, PreferenceKey.videoEditorShowsInspector] {
        store.set(true, forKey: key)
    }
    Preferences.resetAll(in: store)
    // The registration domain is shared by every store in the process, so a cleared key reads its registered default.
    for key in [PreferenceKey.editorShowsLayers, PreferenceKey.videoEditorShowsInspector] {
        #expect(store.persistentDomain(forName: suite.name)?[key] == nil, Comment(rawValue: key))
        #expect(!store.bool(forKey: key), Comment(rawValue: key))
    }
}

/// Every test's `remove()` synchronizes, so a key one test removes must stay removed when another test synchronizes in
/// between (#777).
@Test func aTestStoreKeepsARemovedKeyRemovedWhenAnotherSynchronizes() throws {
    let suite = try TestDefaults()
    let other = try TestDefaults()
    defer {
        suite.remove()
        other.remove()
    }
    let key = "testDefaultsIsolation"
    suite.store.set(true, forKey: key)
    other.store.synchronize()
    suite.store.removeObject(forKey: key)
    #expect(suite.store.object(forKey: key) == nil)
}

@Test func storedCountdownOutsideTheOffersReadsAsOff() throws {
    let suite = try TestDefaults()
    let store = suite.store
    defer { suite.remove() }
    let prefs = Preferences(store: store)
    store.set(5, forKey: PreferenceKey.recordingCountdown)
    #expect(prefs.recordingCountdown == 5)
    store.set(4, forKey: PreferenceKey.recordingCountdown)
    #expect(prefs.recordingCountdown == 0)
}

@Test func savedSettingsMarkSomeoneWhoUsedShotBefore() {
    #expect(Preferences.hasSavedSettings([PreferenceKey.gaveBackTextCaptureKey]))
    #expect(Preferences.hasSavedSettings([PreferenceKey.saveFolder]))
    #expect(Preferences.hasSavedSettings(["hotkey.capture-text"]))
}

@Test func keysMacOSAndSparkleSaveDoNotMarkSomeoneWhoUsedShotBefore() {
    #expect(!Preferences.hasSavedSettings([]))
    #expect(!Preferences.hasSavedSettings(["NSStatusItem Preferred Position Item-0", "NSWindow Frame Shot", "SUHasLaunchedBefore"]))
}

@Test func resettingSettingsKeepsTheOnboardingProgress() throws {
    let suite = try TestDefaults()
    let store = suite.store
    defer { suite.remove() }
    store.set(OnboardingProgress.done.rawValue, forKey: PreferenceKey.onboarding)
    Preferences.resetAll(in: store)
    #expect(store.persistentDomain(forName: suite.name)?[PreferenceKey.onboarding] as? String == "done")
}

@Test func removingTheProviderSettingsClearsEveryKeyItSaved() throws {
    let store = try #require(UserDefaults(suiteName: "provider-\(UUID().uuidString)"))
    for key in LegacyProviderSettings.keys {
        store.set("x", forKey: key)
    }
    store.set("kept", forKey: PreferenceKey.sendToAgentPreset)
    LegacyProviderSettings.remove(from: store, keychainService: "dev.lorcan.Shot.tests.\(UUID().uuidString)")
    for key in LegacyProviderSettings.keys {
        #expect(store.object(forKey: key) == nil)
    }
    #expect(store.string(forKey: PreferenceKey.sendToAgentPreset) == "kept")
}
