import Foundation

public enum PreferenceKey {
    public static let playSound = "playSound"
    public static let saveFolder = "saveFolder"
    public static let filePrefix = "filePrefix"
    public static let imageFormat = "imageFormat"
    public static let downscaleRetina = "downscaleRetina"
    public static let saveAfterCapture = "saveAfterCapture"
    public static let copyAfterCapture = "copyAfterCapture"
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
    public static let recordMicrophone = "recordMicrophone"
    public static let microphoneDeviceID = "microphoneDeviceID"
    public static let recordSystemAudio = "recordSystemAudio"
    public static let showRecordingBorder = "showRecordingBorder"
    public static let copyAfterRecording = "copyAfterRecording"
    public static let recordCamera = "recordCamera"
    public static let cameraDeviceID = "cameraDeviceID"
    public static let cameraSize = "cameraSize"
    public static let replacesSystemScreenshots = "replacesSystemScreenshots"
    public static let videoExportFormat = "videoExportFormat"
    public static let gifFrameRate = "gifFrameRate"
    public static let gifWidth = "gifWidth"
    public static let editorTool = "editorTool"
    public static let editorColor = "editorColor"
    public static let editorNoteColor = "editorNoteColor"
    public static let editorFill = "editorFill"
    public static let editorRecentColors = "editorRecentColors"
    public static let editorWidth = "editorWidth"
    public static let editorShape = "editorShape"
    public static let editorRedaction = "editorRedaction"
    public static let editorRedactionAmount = "editorRedactionAmount"
    public static let editorSpotlight = "editorSpotlight"
    public static let galleryTileSize = "galleryTileSize"
    /// True while the macOS screenshot shortcuts are off because Shot turned them off. Not a
    /// setting, so resetting settings keeps it and Shot can still give the keys back.
    public static let disabledSystemScreenshots = "disabledSystemScreenshots"
    /// True once Shot has given ⌘⇧6 back to macOS, so it does that only once.
    public static let gaveBackTextCaptureKey = "gaveBackTextCaptureKey"

    public static func hotkey(_ action: ShotAction) -> String { "hotkey.\(action.rawValue)" }
}

public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg

    public var fileExtension: String { self == .png ? "png" : "jpg" }

    public init(fileExtension: String) {
        self = ["jpg", "jpeg"].contains(fileExtension.lowercased()) ? .jpeg : .png
    }
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
            PreferenceKey.recordingFPS: 60,
            PreferenceKey.recordShowsCursor: true,
            PreferenceKey.recordMicrophone: false,
            PreferenceKey.microphoneDeviceID: "",
            PreferenceKey.recordSystemAudio: false,
            PreferenceKey.showRecordingBorder: true,
            PreferenceKey.copyAfterRecording: true,
            PreferenceKey.recordCamera: false,
            PreferenceKey.cameraDeviceID: "",
            PreferenceKey.cameraSize: CameraBubbleSize.medium.rawValue,
            PreferenceKey.replacesSystemScreenshots: true,
            PreferenceKey.videoExportFormat: VideoExportOptions().format.rawValue,
            PreferenceKey.gifFrameRate: VideoExportOptions().gifFrameRate,
            PreferenceKey.gifWidth: VideoExportOptions().gifWidth,
            PreferenceKey.editorTool: EditorStyle().tool.rawValue,
            PreferenceKey.editorColor: Data(),
            PreferenceKey.editorNoteColor: Data(),
            PreferenceKey.editorFill: Data(),
            PreferenceKey.editorRecentColors: Data(),
            PreferenceKey.editorWidth: EditorStyle().widthIndex,
            PreferenceKey.editorShape: EditorStyle().shape.rawValue,
            PreferenceKey.editorRedaction: EditorStyle().redaction.rawValue,
            PreferenceKey.editorRedactionAmount: Double(EditorStyle().redactionAmount),
            PreferenceKey.editorSpotlight: Data(),
            PreferenceKey.galleryTileSize: Gallery.defaultTileSize,
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

    /// Removes every stored value so the registered defaults apply again.
    public static func resetAll(in store: UserDefaults = .standard) {
        for key in defaults.keys {
            store.removeObject(forKey: key)
        }
    }

    /// Deletes the shortcut saved for text capture, which Shot no longer has.
    public static func removeTextCapture(in store: UserDefaults = .standard) {
        store.removeObject(forKey: "hotkey.capture-text")
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
        if style.tool.isDrawing {
            store.set(style.tool.rawValue, forKey: PreferenceKey.editorTool)
        }
        store.set(try? JSONEncoder().encode(style.color), forKey: PreferenceKey.editorColor)
        store.set(try? JSONEncoder().encode(style.noteColor), forKey: PreferenceKey.editorNoteColor)
        store.set(style.fill.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: PreferenceKey.editorFill)
        store.set(try? JSONEncoder().encode(style.recentColors), forKey: PreferenceKey.editorRecentColors)
        store.set(style.widthIndex, forKey: PreferenceKey.editorWidth)
        store.set(style.shape.rawValue, forKey: PreferenceKey.editorShape)
        store.set(style.redaction.rawValue, forKey: PreferenceKey.editorRedaction)
        store.set(Double(style.redactionAmount), forKey: PreferenceKey.editorRedactionAmount)
        store.set(try? JSONEncoder().encode(style.spotlight), forKey: PreferenceKey.editorSpotlight)
    }

    public static func resetHotkeys(in store: UserDefaults = .standard) {
        for action in ShotAction.allCases {
            store.removeObject(forKey: PreferenceKey.hotkey(action))
        }
    }

    public var playSound: Bool { store.bool(forKey: PreferenceKey.playSound) }
    public var saveFolder: URL { URL(fileURLWithPath: store.string(forKey: PreferenceKey.saveFolder) ?? Self.defaultSaveFolder) }

    public var filePrefix: String {
        let trimmed = (store.string(forKey: PreferenceKey.filePrefix) ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.defaultFilePrefix : trimmed.replacingOccurrences(of: "/", with: "-")
    }

    public var imageFormat: ImageFormat { ImageFormat(rawValue: store.string(forKey: PreferenceKey.imageFormat) ?? "") ?? .png }
    public var downscaleRetina: Bool { store.bool(forKey: PreferenceKey.downscaleRetina) }
    public var saveAfterCapture: Bool { store.bool(forKey: PreferenceKey.saveAfterCapture) }
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
    public var recordMicrophone: Bool { store.bool(forKey: PreferenceKey.recordMicrophone) }

    /// Empty means the system default microphone.
    public var microphoneDeviceID: String { store.string(forKey: PreferenceKey.microphoneDeviceID) ?? "" }

    public var recordSystemAudio: Bool { store.bool(forKey: PreferenceKey.recordSystemAudio) }
    public var showRecordingBorder: Bool { store.bool(forKey: PreferenceKey.showRecordingBorder) }
    public var copyAfterRecording: Bool { store.bool(forKey: PreferenceKey.copyAfterRecording) }

    public var recordCamera: Bool { store.bool(forKey: PreferenceKey.recordCamera) }

    /// Empty means the system default camera.
    public var cameraDeviceID: String { store.string(forKey: PreferenceKey.cameraDeviceID) ?? "" }

    public var replacesSystemScreenshots: Bool { store.bool(forKey: PreferenceKey.replacesSystemScreenshots) }
    public var disabledSystemScreenshots: Bool { store.bool(forKey: PreferenceKey.disabledSystemScreenshots) }
    public var gaveBackTextCaptureKey: Bool { store.bool(forKey: PreferenceKey.gaveBackTextCaptureKey) }

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
            store.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
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
            fill: decoded(PreferenceKey.editorFill),
            widthIndex: index(PreferenceKey.editorWidth, in: EditorStyle.widths.indices, default: defaults.widthIndex),
            recentColors: decoded(PreferenceKey.editorRecentColors, as: [RGBA].self).map { Array($0.prefix(EditorStyle.maxRecentColors)) } ?? defaults.recentColors,
            shape: BoxShape(rawValue: store.string(forKey: PreferenceKey.editorShape) ?? "") ?? defaults.shape,
            redaction: Redaction(rawValue: store.string(forKey: PreferenceKey.editorRedaction) ?? "") ?? defaults.redaction,
            redactionAmount: (store.object(forKey: PreferenceKey.editorRedactionAmount) as? Double)
                .flatMap { Redaction.amounts.contains(CGFloat($0)) ? CGFloat($0) : nil } ?? defaults.redactionAmount,
            spotlight: decoded(PreferenceKey.editorSpotlight) ?? defaults.spotlight
        )
    }

    public var galleryTileSize: Double {
        Gallery.tileSizes.contains(store.double(forKey: PreferenceKey.galleryTileSize)) ? store.double(forKey: PreferenceKey.galleryTileSize) : Gallery.defaultTileSize
    }

    public var cameraSize: CameraBubbleSize {
        CameraBubbleSize(rawValue: store.string(forKey: PreferenceKey.cameraSize) ?? "") ?? .medium
    }

    /// `nil` means the user cleared the shortcut.
    public func hotkey(for action: ShotAction) -> KeyCombo? {
        KeyCombo(encoded: store.string(forKey: PreferenceKey.hotkey(action)) ?? "")
    }
}
