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
    public static let showMagnifier = "showMagnifier"
    public static let showCrosshair = "showCrosshair"
    public static let windowShadow = "windowShadow"
    public static let quickAccessPosition = "quickAccessPosition"
    public static let quickAccessDuration = "quickAccessDuration"
    public static let recordingFPS = "recordingFPS"
    public static let recordShowsCursor = "recordShowsCursor"
    public static let recordMicrophone = "recordMicrophone"
    public static let recordSystemAudio = "recordSystemAudio"
    public static let showRecordingBorder = "showRecordingBorder"
    public static let recordCamera = "recordCamera"
    public static let cameraDeviceID = "cameraDeviceID"
    public static let cameraSize = "cameraSize"

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

/// Typed read access to settings; `@AppStorage` in views uses the same keys and `Preferences.defaults`.
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
            PreferenceKey.showMagnifier: true,
            PreferenceKey.showCrosshair: true,
            PreferenceKey.windowShadow: true,
            PreferenceKey.quickAccessPosition: QuickAccessPosition.left.rawValue,
            PreferenceKey.quickAccessDuration: 8.0,
            PreferenceKey.recordingFPS: 60,
            PreferenceKey.recordShowsCursor: true,
            PreferenceKey.recordMicrophone: false,
            PreferenceKey.recordSystemAudio: false,
            PreferenceKey.showRecordingBorder: true,
            PreferenceKey.recordCamera: false,
            PreferenceKey.cameraDeviceID: "",
            PreferenceKey.cameraSize: CameraBubbleSize.medium.rawValue,
        ]
        for action in ShotAction.allCases {
            values[PreferenceKey.hotkey(action)] = action.defaultCombo.encoded
        }
        return values
    }

    let store: UserDefaults

    /// Call `registerDefaults()` on `store` once before reading.
    public init(store: UserDefaults = .standard) {
        self.store = store
    }

    public static func registerDefaults(in store: UserDefaults = .standard) {
        store.register(defaults: defaults)
    }

    /// Removes every stored value so the registered defaults apply again.
    public static func resetAll(in store: UserDefaults = .standard) {
        for key in defaults.keys {
            store.removeObject(forKey: key)
        }
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
    public var recordSystemAudio: Bool { store.bool(forKey: PreferenceKey.recordSystemAudio) }
    public var showRecordingBorder: Bool { store.bool(forKey: PreferenceKey.showRecordingBorder) }

    public var recordCamera: Bool { store.bool(forKey: PreferenceKey.recordCamera) }

    /// Empty means the system default camera.
    public var cameraDeviceID: String { store.string(forKey: PreferenceKey.cameraDeviceID) ?? "" }

    public var cameraSize: CameraBubbleSize {
        CameraBubbleSize(rawValue: store.string(forKey: PreferenceKey.cameraSize) ?? "") ?? .medium
    }

    /// `nil` means the user cleared the shortcut.
    public func hotkey(for action: ShotAction) -> KeyCombo? {
        KeyCombo(encoded: store.string(forKey: PreferenceKey.hotkey(action)) ?? "")
    }
}
