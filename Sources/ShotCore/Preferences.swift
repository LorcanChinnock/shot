import Foundation

public enum PreferenceKey {
    public static let saveFolder = "saveFolder"
    public static let saveAfterCapture = "saveAfterCapture"
    public static let copyAfterCapture = "copyAfterCapture"
    public static let quickAccessAfterCapture = "quickAccessAfterCapture"
    public static let quickAccessDuration = "quickAccessDuration"
    public static let windowShadow = "windowShadow"
    public static let recordingFPS = "recordingFPS"
    public static let recordMicrophone = "recordMicrophone"
    public static let recordShowsCursor = "recordShowsCursor"

    public static func hotkey(_ action: ShotAction) -> String { "hotkey.\(action.rawValue)" }
}

/// Typed read access to settings; `@AppStorage` in views uses the same keys and `Preferences.defaults`.
public struct Preferences {
    public static var defaultSaveFolder: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Shot").path
    }

    public static var defaults: [String: Any] {
        var values: [String: Any] = [
            PreferenceKey.saveFolder: defaultSaveFolder,
            PreferenceKey.saveAfterCapture: true,
            PreferenceKey.copyAfterCapture: true,
            PreferenceKey.quickAccessAfterCapture: true,
            PreferenceKey.quickAccessDuration: 8.0,
            PreferenceKey.windowShadow: true,
            PreferenceKey.recordingFPS: 60,
            PreferenceKey.recordMicrophone: false,
            PreferenceKey.recordShowsCursor: true,
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

    public var saveFolder: URL { URL(fileURLWithPath: store.string(forKey: PreferenceKey.saveFolder) ?? Self.defaultSaveFolder) }
    public var saveAfterCapture: Bool { store.bool(forKey: PreferenceKey.saveAfterCapture) }
    public var copyAfterCapture: Bool { store.bool(forKey: PreferenceKey.copyAfterCapture) }
    public var quickAccessAfterCapture: Bool { store.bool(forKey: PreferenceKey.quickAccessAfterCapture) }
    public var quickAccessDuration: Double { store.double(forKey: PreferenceKey.quickAccessDuration) }
    public var windowShadow: Bool { store.bool(forKey: PreferenceKey.windowShadow) }
    public var recordingFPS: Int { store.integer(forKey: PreferenceKey.recordingFPS) }
    public var recordMicrophone: Bool { store.bool(forKey: PreferenceKey.recordMicrophone) }
    public var recordShowsCursor: Bool { store.bool(forKey: PreferenceKey.recordShowsCursor) }

    /// `nil` means the user cleared the shortcut.
    public func hotkey(for action: ShotAction) -> KeyCombo? {
        KeyCombo(encoded: store.string(forKey: PreferenceKey.hotkey(action)) ?? "")
    }
}
