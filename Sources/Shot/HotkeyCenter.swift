import Carbon.HIToolbox
import os
import ShotCore

private let log = Logger.shot("hotkeys")

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onPress: ((ShotAction) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    private var registered: [ShotAction: KeyCombo] = [:]
    /// True while the shortcut recorder listens, so global hotkeys don't swallow the keystroke.
    private var isSuspended = false
    private var temporaryRef: EventHotKeyRef?
    private var onTemporaryPress: (() -> Void)?
    private static let temporaryID = UInt32.max

    func reloadFromPreferences(force: Bool = false) {
        guard !isSuspended else {
            return
        }
        let prefs = Preferences()
        let bindings = ShotAction.allCases.reduce(into: [ShotAction: KeyCombo]()) { $0[$1] = prefs.hotkey(for: $1) }
        if force || bindings != registered {
            register(bindings)
        }
    }

    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        reloadFromPreferences(force: true)
    }

    /// Takes `combo` from every app until `unregisterTemporary()`, for a key that only means something briefly,
    /// such as ⌘Z while a toast offers Undo. Replaces any earlier temporary key. False when it couldn't be registered.
    @discardableResult
    func registerTemporary(_ combo: KeyCombo, onPress: @escaping () -> Void) -> Bool {
        unregisterTemporary()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5348_4F54), id: Self.temporaryID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for temporary \(combo.displayString, privacy: .public): \(status)")
            return false
        }
        temporaryRef = ref
        onTemporaryPress = onPress
        return true
    }

    func unregisterTemporary() {
        if let temporaryRef {
            UnregisterEventHotKey(temporaryRef)
        }
        temporaryRef = nil
        onTemporaryPress = nil
    }

    private func register(_ bindings: [ShotAction: KeyCombo]) {
        unregisterAll()
        installHandlerIfNeeded()
        registered = bindings
        var failed: [String] = []
        for (action, combo) in bindings {
            guard let index = ShotAction.allCases.firstIndex(of: action) else {
                continue
            }
            let id = EventHotKeyID(signature: OSType(0x5348_4F54), id: UInt32(index))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                log.error("RegisterEventHotKey failed for \(action.rawValue, privacy: .public): \(status)")
                failed.append(combo.displayString)
            }
        }
        if !failed.isEmpty {
            // Usually another app owns the shortcut, or two Shot actions share it.
            Toast.error("Shortcut unavailable: \(failed.sorted().joined(separator: ", ")). Another app may use it, so choose a different one in Settings › Shortcuts.")
        }
        log.notice("Registered \(self.refs.count) hotkeys")
    }

    private func unregisterAll() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        registered = [:]
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else {
            return
        }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            // Carbon dispatches hotkey events on the main thread.
            MainActor.assumeIsolated {
                if id.id == HotkeyCenter.temporaryID {
                    HotkeyCenter.shared.onTemporaryPress?()
                } else if ShotAction.allCases.indices.contains(index) {
                    HotkeyCenter.shared.onPress?(ShotAction.allCases[index])
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
