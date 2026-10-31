import Foundation
import os

private let log = Logger.shot("preferences")

public enum PreferenceKey {
    public static let playSound = "playSound"
    public static let saveFolder = "saveFolder"
    public static let filePrefix = "filePrefix"
    public static let imageFormat = "imageFormat"
    public static let downscaleRetina = "downscaleRetina"
    public static let saveAfterCapture = "saveAfterCapture"
    public static let copyAfterCapture = "copyAfterCapture"
    public static let editorSavesOverOriginal = "editorSavesOverOriginal"
    public static let quickAccessAfterCapture = "quickAccessAfterCapture"
    public static let openEditorAfterCapture = "openEditorAfterCapture"
    public static let captureShowsCursor = "captureShowsCursor"
    public static let hidesShotUI = "hidesShotUI"
    public static let excludesMenuBar = "excludesMenuBar"
    public static let showMagnifier = "showMagnifier"
    public static let showCrosshair = "showCrosshair"
    public static let windowShadow = "windowShadow"
    public static let quickAccessPosition = "quickAccessPosition"
    public static let quickAccessDuration = "quickAccessDuration"
    public static let recordingFPS = "recordingFPS"
    public static let recordShowsCursor = "recordShowsCursor"
    public static let recordShowsClicks = "recordShowsClicks"
    public static let recordMicrophone = "recordMicrophone"
    public static let microphoneDeviceID = "microphoneDeviceID"
    public static let recordSystemAudio = "recordSystemAudio"
    public static let showRecordingBorder = "showRecordingBorder"
    public static let copyAfterRecording = "copyAfterRecording"
    public static let recordCamera = "recordCamera"
    public static let adjustBeforeRecording = "adjustBeforeRecording"
    public static let cameraDeviceID = "cameraDeviceID"
    public static let cameraSize = "cameraSize"
    public static let replacesSystemScreenshots = "replacesSystemScreenshots"
    public static let videoExportFormat = "videoExportFormat"
    public static let gifFrameRate = "gifFrameRate"
    public static let gifWidth = "gifWidth"
    public static let editorTool = "editorTool"
    public static let editorColor = "editorColor"
    public static let editorNoteColor = "editorNoteColor"
    public static let editorHighlightColor = "editorHighlightColor"
    public static let editorFill = "editorFill"
    public static let editorCustomColors = "editorCustomColors"
    public static let editorWidth = "editorWidth"
    public static let editorShape = "editorShape"
    public static let editorRedaction = "editorRedaction"
    public static let editorRedactionAmount = "editorRedactionAmount"
    public static let editorSpotlight = "editorSpotlight"
    public static let editorAlignment = "editorAlignment"
    public static let editorVerticalAlignment = "editorVerticalAlignment"
    public static let editorObjectStyles = "editorObjectStyles"
    /// The shape the editor's crop was last held to.
    public static let editorCropAspect = "editorCropAspect"
    /// The style Use this style for new captures saved; empty while it's off.
    public static let newCaptureStyle = "newCaptureStyle"
    public static let galleryTileSize = "galleryTileSize"
    /// The folder in the save folder new captures go to, by name; empty for the save folder itself.
    public static let captureSubfolder = "captureSubfolder"
    /// Whether the gallery shows its sidebar of folders; off until someone opens it.
    public static let galleryShowsSidebar = "galleryShowsSidebar"
    /// How wide the gallery's folder sidebar is, in points.
    public static let galleryFolderSidebarWidth = "galleryFolderSidebarWidth"
    /// How wide the window's sidebar of sections is, in points, and whether it's shrunk to icons.
    public static let appSidebarWidth = "appSidebarWidth"
    public static let appSidebarCollapsed = "appSidebarCollapsed"
    /// How large Shot draws its own text, a `TextSize`.
    public static let textSize = "textSize"
    /// Whether Shot follows the system appearance, an `AppearanceMode`.
    public static let appearance = "appearance"
    /// What the screenshot and recording overlays last picked, a `CaptureTarget`, which they open on next time.
    public static let screenshotTarget = "screenshotTarget"
    public static let recordTarget = "recordTarget"
    /// True while the macOS screenshot shortcuts are off because Shot turned them off. Not a
    /// setting, so resetting settings keeps it and Shot can still give the keys back.
    public static let disabledSystemScreenshots = "disabledSystemScreenshots"
    /// True once Shot has given ⌘⇧6 back to macOS, so it does that only once.
    public static let gaveBackTextCaptureKey = "gaveBackTextCaptureKey"
    /// True once Shot has given ⌘⇧3 back to macOS, so it does that only once.
    public static let gaveBackFullScreenKey = "gaveBackFullScreenKey"
    /// Window layout: whether the photo editor shows its layers, and the video editor its inspector.
    public static let editorShowsLayers = "editorShowsLayers"
    public static let videoEditorShowsInspector = "videoEditorShowsInspector"
    /// How far the welcome window got, an `OnboardingProgress`. Not a setting, so resetting settings keeps it.
    public static let onboarding = "onboarding"

    public static func hotkey(_ action: ShotAction) -> String { "hotkey.\(action.rawValue)" }
}

public enum QuickAccessPosition: String, CaseIterable, Sendable {
    case left, right
}

/// Typed read access to settings; `@Setting` in views uses the same keys and `Preferences.defaults`.
public struct Preferences {
    public static var defaultSaveFolder: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Shot").path
    }

    public static let defaultFilePrefix = "Shot"

    public static var defaults: [String: Any] {
        var values: [String: Any] = [
            PreferenceKey.playSound: true,
            PreferenceKey.saveFolder: defaultSaveFolder,
            PreferenceKey.filePrefix: defaultFilePrefix,
            PreferenceKey.imageFormat: ImageFormat.png.rawValue,
            PreferenceKey.downscaleRetina: false,
            PreferenceKey.saveAfterCapture: true,
            PreferenceKey.copyAfterCapture: true,
            PreferenceKey.editorSavesOverOriginal: true,
            PreferenceKey.quickAccessAfterCapture: true,
            PreferenceKey.openEditorAfterCapture: false,
            PreferenceKey.captureShowsCursor: false,
            PreferenceKey.hidesShotUI: true,
            PreferenceKey.excludesMenuBar: false,
            PreferenceKey.showMagnifier: true,
            PreferenceKey.showCrosshair: true,
            PreferenceKey.windowShadow: true,
            PreferenceKey.quickAccessPosition: QuickAccessPosition.left.rawValue,
            PreferenceKey.quickAccessDuration: 8.0,
            PreferenceKey.recordingFPS: RecordingFrameRate.default,
            PreferenceKey.recordShowsCursor: true,
            PreferenceKey.recordShowsClicks: false,
            PreferenceKey.recordMicrophone: false,
            PreferenceKey.microphoneDeviceID: "",
            PreferenceKey.recordSystemAudio: false,
            PreferenceKey.showRecordingBorder: true,
            PreferenceKey.copyAfterRecording: true,
            PreferenceKey.recordCamera: false,
            PreferenceKey.adjustBeforeRecording: false,
            PreferenceKey.cameraDeviceID: "",
            PreferenceKey.cameraSize: CameraBubbleSize.medium.rawValue,
            PreferenceKey.textSize: TextSize.standard.rawValue,
            PreferenceKey.appearance: AppearanceMode.system.rawValue,
            PreferenceKey.screenshotTarget: CaptureTarget.area.rawValue,
            PreferenceKey.recordTarget: CaptureTarget.area.rawValue,
            PreferenceKey.replacesSystemScreenshots: true,
            PreferenceKey.videoExportFormat: VideoExportOptions().format.rawValue,
            PreferenceKey.gifFrameRate: VideoExportOptions().gifFrameRate,
            PreferenceKey.gifWidth: VideoExportOptions().gifWidth,
            PreferenceKey.editorTool: EditorStyle().tool.rawValue,
            PreferenceKey.editorColor: Data(),
            PreferenceKey.editorNoteColor: Data(),
            PreferenceKey.editorHighlightColor: Data(),
            PreferenceKey.editorFill: Data(),
            PreferenceKey.editorCustomColors: Data(),
            PreferenceKey.editorWidth: EditorStyle().widthIndex,
            PreferenceKey.editorShape: EditorStyle().shape.rawValue,
            PreferenceKey.editorRedaction: EditorStyle().redaction.rawValue,
            PreferenceKey.editorRedactionAmount: Double(EditorStyle().redactionAmount),
            PreferenceKey.editorSpotlight: Data(),
            PreferenceKey.editorAlignment: EditorStyle().alignment.rawValue,
            PreferenceKey.editorVerticalAlignment: EditorStyle().verticalAlignment.rawValue,
            PreferenceKey.editorObjectStyles: Data(),
            PreferenceKey.newCaptureStyle: Data(),
            PreferenceKey.galleryTileSize: Gallery.defaultTileSize,
            PreferenceKey.captureSubfolder: "",
            PreferenceKey.galleryShowsSidebar: false,
            PreferenceKey.galleryFolderSidebarWidth: 200.0,
            PreferenceKey.appSidebarWidth: 196.0,
            PreferenceKey.appSidebarCollapsed: false,
            PreferenceKey.editorShowsLayers: false,
            PreferenceKey.videoEditorShowsInspector: false,
        ]
        for action in ShotAction.allCases {
            values[PreferenceKey.hotkey(action)] = action.defaultCombo?.encoded ?? ""
        }
        return values
    }

    let store: UserDefaults

    /// Call `registerDefaults()` on `store` once before reading.
    public init(store: UserDefaults = .standard) {
        self.store = store
    }

    /// Call again after `replacesSystemScreenshots` changes, so unchanged shortcuts follow it.
    public static func registerDefaults(in store: UserDefaults = .standard) {
        store.register(defaults: defaults)
        let replacing = store.bool(forKey: PreferenceKey.replacesSystemScreenshots)
        var hotkeys: [String: Any] = [:]
        for action in ShotAction.allCases {
            hotkeys[PreferenceKey.hotkey(action)] = action.defaultCombo(replacingSystemScreenshots: replacing)?.encoded ?? ""
        }
        store.register(defaults: hotkeys)
    }

    /// Whether `keys`, the keys saved in Shot's defaults domain, hold any of Shot's own, so Shot was used before. Takes the
    /// saved keys rather than reading `UserDefaults`, which also answers with registered defaults. Call it before
    /// launch writes anything: `gaveBackTextCaptureKey` is saved on every launch, so from then on it's always true.
    public static func hasSavedSettings(_ keys: some Sequence<String>) -> Bool {
        let own = Set(defaults.keys).union([PreferenceKey.disabledSystemScreenshots, PreferenceKey.gaveBackTextCaptureKey])
        return keys.contains { own.contains($0) || $0.hasPrefix("hotkey.") }
    }

    /// Removes every stored value so the registered defaults apply again.
    public static func resetAll(in store: UserDefaults = .standard) {
        for key in defaults.keys {
            store.removeObject(forKey: key)
        }
        // Older versions kept recent custom colours.
        store.removeObject(forKey: "editorRecentColors")
    }

    /// Deletes the shortcut saved for text capture, which Shot no longer has.
    public static func removeTextCapture(in store: UserDefaults = .standard) {
        store.removeObject(forKey: "hotkey.capture-text")
    }

    /// Deletes the language Translate Text remembered, which Shot no longer has.
    public static func removeTranslateTarget(in store: UserDefaults = .standard) {
        store.removeObject(forKey: "translateTarget")
    }

    /// Moves the shortcut saved for Capture Area to Screenshot, then deletes what the separate capture and record
    /// actions and the recording countdown left behind. Capture Full Screen's and Capture Window's go: Tab on the
    /// overlay picks those now.
    public static func migrateCaptureActions(in store: UserDefaults = .standard) {
        if let area = store.string(forKey: "hotkey.capture-area") {
            store.set(area, forKey: PreferenceKey.hotkey(.screenshot))
        }
        for key in ["hotkey.capture-area", "hotkey.capture-fullscreen", "hotkey.capture-window", "hotkey.capture-previous",
                    "hotkey.record-fullscreen", "hotkey.record-window", "recordingCountdown"] {
            store.removeObject(forKey: key)
        }
    }

    /// Deletes the shortcuts saved for actions that are now menu-only, which `hotkey(for:)` ignores anyway.
    public static func removeMenuOnlyHotkeys(in store: UserDefaults = .standard) {
        for action in ShotAction.allCases where !action.hasShortcut {
            store.removeObject(forKey: PreferenceKey.hotkey(action))
        }
    }

    /// Remembers the video editor's format and GIF settings; speed and mute are chosen per video.
    public static func remember(_ options: VideoExportOptions, in store: UserDefaults = .standard) {
        store.set(options.format.rawValue, forKey: PreferenceKey.videoExportFormat)
        store.set(options.gifFrameRate, forKey: PreferenceKey.gifFrameRate)
        store.set(options.gifWidth, forKey: PreferenceKey.gifWidth)
    }

    /// Remembers the editor's tool, colours and width for the next editor window. Select and crop
    /// aren't remembered, so the last drawing tool stays.
    public static func remember(_ style: EditorStyle, in store: UserDefaults = .standard) {
        remember(style, changedFrom: nil, in: store)
    }

    /// Changes the remembered editor style, writing only the values that changed, so another open editor's choices aren't
    /// overwritten with this window's, and a colour dragged in the colour editor writes one key per change, not all of them.
    public static func changeEditorStyle(in store: UserDefaults = .standard, _ change: (inout EditorStyle) -> Void) {
        let old = Preferences(store: store).editorStyle
        var style = old
        change(&style)
        remember(style, changedFrom: old, in: store)
    }

    /// Writes the values of `style` that differ from `old`, or all of them when there's no `old`.
    private static func remember(_ style: EditorStyle, changedFrom old: EditorStyle?, in store: UserDefaults) {
        func changed<T: Equatable>(_ value: (EditorStyle) -> T) -> Bool {
            old.map { value($0) != value(style) } ?? true
        }
        if style.tool.isDrawing, changed(\.tool) {
            store.set(style.tool.rawValue, forKey: PreferenceKey.editorTool)
        }
        if changed(\.color) {
            store.set(try? JSONEncoder().encode(style.color), forKey: PreferenceKey.editorColor)
        }
        if changed(\.noteColor) {
            store.set(try? JSONEncoder().encode(style.noteColor), forKey: PreferenceKey.editorNoteColor)
        }
        if changed(\.highlightColor) {
            store.set(try? JSONEncoder().encode(style.highlightColor), forKey: PreferenceKey.editorHighlightColor)
        }
        if changed(\.fill) {
            store.set(style.fill.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: PreferenceKey.editorFill)
        }
        if changed(\.customColors) {
            store.set(try? JSONEncoder().encode(style.customColors), forKey: PreferenceKey.editorCustomColors)
        }
        if changed(\.widthIndex) {
            store.set(style.widthIndex, forKey: PreferenceKey.editorWidth)
        }
        if changed(\.shape) {
            store.set(style.shape.rawValue, forKey: PreferenceKey.editorShape)
        }
        if changed(\.redaction) {
            store.set(style.redaction.rawValue, forKey: PreferenceKey.editorRedaction)
        }
        if changed(\.redactionAmount) {
            store.set(Double(style.redactionAmount), forKey: PreferenceKey.editorRedactionAmount)
        }
        if changed(\.spotlight) {
            store.set(try? JSONEncoder().encode(style.spotlight), forKey: PreferenceKey.editorSpotlight)
        }
        if changed(\.alignment) {
            store.set(style.alignment.rawValue, forKey: PreferenceKey.editorAlignment)
        }
        if changed(\.verticalAlignment) {
            store.set(style.verticalAlignment.rawValue, forKey: PreferenceKey.editorVerticalAlignment)
        }
        if changed(\.objectStyles) {
            store.set(try? JSONEncoder().encode(style.objectStyles), forKey: PreferenceKey.editorObjectStyles)
        }
    }

    public static func resetHotkeys(in store: UserDefaults = .standard) {
        for action in ShotAction.allCases {
            store.removeObject(forKey: PreferenceKey.hotkey(action))
        }
    }

    public var playSound: Bool { store.bool(forKey: PreferenceKey.playSound) }
    public var saveFolder: URL { URL(fileURLWithPath: store.string(forKey: PreferenceKey.saveFolder) ?? Self.defaultSaveFolder) }

    public var filePrefix: String { Self.sanitizedPrefix(store.string(forKey: PreferenceKey.filePrefix) ?? "") }

    /// The file name prefix typed in Settings as file names use it: trimmed of spaces and of dots, which would hide the
    /// file, the default when empty, and with no `/` or `:`, which Finder shows as each other.
    public static func sanitizedPrefix(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return trimmed.isEmpty ? defaultFilePrefix : trimmed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    public var imageFormat: ImageFormat { ImageFormat(rawValue: store.string(forKey: PreferenceKey.imageFormat) ?? "") ?? .png }
    public var downscaleRetina: Bool { store.bool(forKey: PreferenceKey.downscaleRetina) }
    public var saveAfterCapture: Bool { store.bool(forKey: PreferenceKey.saveAfterCapture) }
    /// The path of the folder in the save folder that new captures go to, picked in the gallery; empty for the save folder itself.
    public var captureSubfolder: String { store.string(forKey: PreferenceKey.captureSubfolder) ?? "" }
    /// Where captures and recordings are written: the save folder, or the folder in it picked in the gallery, or a
    /// temporary one Quick Access and the editors can still open.
    public var captureFolder: URL { saveAfterCapture ? Gallery.captureFolder(in: saveFolder, subfolder: captureSubfolder) : TemporaryCaptures.folder }
    public var editorSavesOverOriginal: Bool { store.bool(forKey: PreferenceKey.editorSavesOverOriginal) }

    /// Whether `file` is a capture Shot made, one in the save folder or any folder in it, or in the temporary
    /// one, which is the only kind the editor's Save goes over.
    public func isOwnCapture(_ file: URL) -> Bool {
        let folder = file.deletingLastPathComponent().resolvingSymlinksInPath().path
        let root = saveFolder.resolvingSymlinksInPath().path
        return folder == root || folder.hasPrefix(root.hasSuffix("/") ? root : root + "/") || TemporaryCaptures.isTemporary(file)
    }
    public var copyAfterCapture: Bool { store.bool(forKey: PreferenceKey.copyAfterCapture) }
    public var quickAccessAfterCapture: Bool { store.bool(forKey: PreferenceKey.quickAccessAfterCapture) }
    public var openEditorAfterCapture: Bool { store.bool(forKey: PreferenceKey.openEditorAfterCapture) }
    public var captureShowsCursor: Bool { store.bool(forKey: PreferenceKey.captureShowsCursor) }
    /// Keeps Quick Access cards, toasts and other Shot windows out of screenshots and recordings; the camera bubble always shows.
    public var hidesShotUI: Bool { store.bool(forKey: PreferenceKey.hidesShotUI) }
    /// Crops the menu bar, and the notch beside it, off full-screen screenshots and recordings.
    public var excludesMenuBar: Bool { store.bool(forKey: PreferenceKey.excludesMenuBar) }
    public var showMagnifier: Bool { store.bool(forKey: PreferenceKey.showMagnifier) }
    public var showCrosshair: Bool { store.bool(forKey: PreferenceKey.showCrosshair) }
    public var windowShadow: Bool { store.bool(forKey: PreferenceKey.windowShadow) }

    public var quickAccessPosition: QuickAccessPosition {
        QuickAccessPosition(rawValue: store.string(forKey: PreferenceKey.quickAccessPosition) ?? "") ?? .left
    }

    public var quickAccessDuration: Double { store.double(forKey: PreferenceKey.quickAccessDuration) }
    public var recordingFPS: Int { store.integer(forKey: PreferenceKey.recordingFPS) }
    public var recordShowsCursor: Bool { store.bool(forKey: PreferenceKey.recordShowsCursor) }
    public var recordShowsClicks: Bool { store.bool(forKey: PreferenceKey.recordShowsClicks) }
    public var recordMicrophone: Bool { store.bool(forKey: PreferenceKey.recordMicrophone) }

    /// Empty means the system default microphone.
    public var microphoneDeviceID: String { store.string(forKey: PreferenceKey.microphoneDeviceID) ?? "" }

    public var recordSystemAudio: Bool { store.bool(forKey: PreferenceKey.recordSystemAudio) }
    public var showRecordingBorder: Bool { store.bool(forKey: PreferenceKey.showRecordingBorder) }
    public var copyAfterRecording: Bool { store.bool(forKey: PreferenceKey.copyAfterRecording) }

    public var recordCamera: Bool { store.bool(forKey: PreferenceKey.recordCamera) }
    /// Shows the setup panel, with frame handles and option toggles, before each recording.
    public var adjustBeforeRecording: Bool { store.bool(forKey: PreferenceKey.adjustBeforeRecording) }

    /// Empty means the system default camera.
    public var cameraDeviceID: String { store.string(forKey: PreferenceKey.cameraDeviceID) ?? "" }

    public var replacesSystemScreenshots: Bool { store.bool(forKey: PreferenceKey.replacesSystemScreenshots) }
    public var disabledSystemScreenshots: Bool { store.bool(forKey: PreferenceKey.disabledSystemScreenshots) }
    public var gaveBackTextCaptureKey: Bool { store.bool(forKey: PreferenceKey.gaveBackTextCaptureKey) }
    public var gaveBackFullScreenKey: Bool { store.bool(forKey: PreferenceKey.gaveBackFullScreenKey) }

    /// The last-used export settings, which Quick Access's Export GIF also uses, at normal speed with sound.
    public var videoExportOptions: VideoExportOptions {
        let defaults = VideoExportOptions()
        let fps = store.integer(forKey: PreferenceKey.gifFrameRate)
        let width = store.integer(forKey: PreferenceKey.gifWidth)
        return VideoExportOptions(
            format: VideoExportFormat(rawValue: store.string(forKey: PreferenceKey.videoExportFormat) ?? "") ?? defaults.format,
            gifFrameRate: VideoExportOptions.gifFrameRates.contains(fps) ? fps : defaults.gifFrameRate,
            gifWidth: VideoExportOptions.gifWidths.contains(width) ? width : defaults.gifWidth
        )
    }

    /// The style the last editor used. Each value this version doesn't offer falls back to its default on its own.
    public var editorStyle: EditorStyle {
        let defaults = EditorStyle()
        func index(_ key: String, in range: Range<Int>, default value: Int) -> Int {
            (store.object(forKey: key) as? Int).flatMap { range.contains($0) ? $0 : nil } ?? value
        }
        func decoded<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
            guard let data = store.data(forKey: key) else { return nil }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                log.error("Couldn't decode \(key, privacy: .public), using the default: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        // Older versions saved a colour as an index into the presets.
        func colour(_ key: String, default value: RGBA) -> RGBA {
            decoded(key) ?? (store.object(forKey: key) as? Int).flatMap { RGBA.presets.indices.contains($0) ? RGBA.presets[$0] : nil } ?? value
        }
        // Older versions had a tool for each shape and for pixelate and blur.
        let legacyTools: [String: EditorTool] = ["rect": .shape, "ellipse": .shape, "pixelate": .redact, "blur": .redact]
        let toolName = store.string(forKey: PreferenceKey.editorTool) ?? ""
        let tool = EditorTool(rawValue: toolName) ?? legacyTools[toolName]
        return EditorStyle(
            tool: tool.flatMap { $0.isDrawing ? $0 : nil } ?? defaults.tool,
            color: colour(PreferenceKey.editorColor, default: defaults.color),
            noteColor: colour(PreferenceKey.editorNoteColor, default: defaults.noteColor),
            highlightColor: decoded(PreferenceKey.editorHighlightColor) ?? defaults.highlightColor,
            fill: decoded(PreferenceKey.editorFill),
            widthIndex: index(PreferenceKey.editorWidth, in: EditorStyle.widths.indices, default: defaults.widthIndex),
            customColors: decoded(PreferenceKey.editorCustomColors) ?? defaults.customColors,
            // `rounded` was a shape of its own before every shape could be rounded.
            shape: store.string(forKey: PreferenceKey.editorShape).flatMap { BoxShape(rawValue: $0 == "rounded" ? "rectangle" : $0) } ?? defaults.shape,
            redaction: Redaction(rawValue: store.string(forKey: PreferenceKey.editorRedaction) ?? "") ?? defaults.redaction,
            redactionAmount: (store.object(forKey: PreferenceKey.editorRedactionAmount) as? Double)
                .flatMap { Redaction.amounts.contains(CGFloat($0)) ? CGFloat($0) : nil } ?? defaults.redactionAmount,
            spotlight: decoded(PreferenceKey.editorSpotlight) ?? defaults.spotlight,
            alignment: TextAlign(rawValue: store.string(forKey: PreferenceKey.editorAlignment) ?? "") ?? defaults.alignment,
            verticalAlignment: VerticalTextAlign(rawValue: store.string(forKey: PreferenceKey.editorVerticalAlignment) ?? "") ?? defaults.verticalAlignment,
            objectStyles: decoded(PreferenceKey.editorObjectStyles) ?? defaults.objectStyles
        )
    }

    /// The style new captures open and copy with, when Use this style for new captures is on; `nil` when it's off.
    public var newCaptureStyle: CopiedStyle? {
        guard let data = store.data(forKey: PreferenceKey.newCaptureStyle), !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(CopiedStyle.self, from: data)
        } catch {
            log.error("Couldn't decode \(PreferenceKey.newCaptureStyle, privacy: .public), using the default: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Turns Use this style for new captures on with `style`, or off when it's `nil`.
    public static func styleNewCaptures(with style: CopiedStyle?, in store: UserDefaults = .standard) {
        store.set(style.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: PreferenceKey.newCaptureStyle)
    }

    public var galleryTileSize: Double {
        Gallery.tileSizes.contains(store.double(forKey: PreferenceKey.galleryTileSize)) ? store.double(forKey: PreferenceKey.galleryTileSize) : Gallery.defaultTileSize
    }


    public var textSize: TextSize {
        TextSize(rawValue: store.string(forKey: PreferenceKey.textSize) ?? "") ?? .standard
    }

    public var appearance: AppearanceMode {
        AppearanceMode(rawValue: store.string(forKey: PreferenceKey.appearance) ?? "") ?? .system
    }

    public var screenshotTarget: CaptureTarget {
        get { CaptureTarget(rawValue: store.string(forKey: PreferenceKey.screenshotTarget) ?? "") ?? .area }
        nonmutating set { store.set(newValue.rawValue, forKey: PreferenceKey.screenshotTarget) }
    }

    public var recordTarget: CaptureTarget {
        get { CaptureTarget(rawValue: store.string(forKey: PreferenceKey.recordTarget) ?? "") ?? .area }
        nonmutating set { store.set(newValue.rawValue, forKey: PreferenceKey.recordTarget) }
    }

    public var cameraSize: CameraBubbleSize {
        CameraBubbleSize(rawValue: store.string(forKey: PreferenceKey.cameraSize) ?? "") ?? .medium
    }

    /// `nil` means the user cleared the shortcut.
    public func hotkey(for action: ShotAction) -> KeyCombo? {
        guard action.hasShortcut else {
            return nil
        }
        return KeyCombo(encoded: store.string(forKey: PreferenceKey.hotkey(action)) ?? "")
    }
}
