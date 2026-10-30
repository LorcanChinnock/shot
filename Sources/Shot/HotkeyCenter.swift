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
    /// Keys taken for a while, by id, counted down from the top so they never meet an action's index.
    private var temporaries: [UInt32: (ref: EventHotKeyRef, onPress: () -> Void)] = [:]
    private var nextTemporaryID = UInt32.max
    private static let firstTemporaryID = UInt32.max - 100_000
    private var toastKey: TemporaryHotkeys?

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
    /// such as ⌘Z while a toast offers Undo. Replaces any earlier such key. False when it couldn't be registered.
    @discardableResult
    func registerTemporary(_ combo: KeyCombo, onPress: @escaping () -> Void) -> Bool {
        unregisterTemporary()
        toastKey = registerTemporary(combos: [combo]) { _ in onPress() }
        return toastKey != nil
    }

    func unregisterTemporary() {
        toastKey?.unregister()
        toastKey = nil
    }

    /// Takes `combos` from every app until the token is unregistered, as a scrolling capture takes Return and Esc.
    /// `onPress` gets the combo pressed. `nil` when none could be registered; the rest are kept.
    func registerTemporary(combos: [KeyCombo], onPress: @escaping (KeyCombo) -> Void) -> TemporaryHotkeys? {
        installHandlerIfNeeded()
        let token = TemporaryHotkeys(center: self)
        for combo in combos {
            if nextTemporaryID <= Self.firstTemporaryID {
                nextTemporaryID = UInt32.max
            }
            let id = nextTemporaryID
            nextTemporaryID -= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x5348_4F54), id: id), GetEventDispatcherTarget(), 0, &ref)
            guard status == noErr, let ref else {
                log.error("RegisterEventHotKey failed for temporary \(combo.displayString, privacy: .public): \(status)")
                continue
            }
            temporaries[id] = (ref, { onPress(combo) })
            token.ids.append(id)
        }
        return token.ids.isEmpty ? nil : token
    }

    fileprivate func unregister(_ token: TemporaryHotkeys) {
        for id in token.ids {
            if let entry = temporaries.removeValue(forKey: id) {
                UnregisterEventHotKey(entry.ref)
            }
        }
        token.ids = []
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
                if id.id > HotkeyCenter.firstTemporaryID {
                    HotkeyCenter.shared.temporaries[id.id]?.onPress()
                } else if ShotAction.allCases.indices.contains(index) {
                    HotkeyCenter.shared.onPress?(ShotAction.allCases[index])
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Keys taken for a while; `unregister()` gives them back.
@MainActor
final class TemporaryHotkeys {
    fileprivate var ids: [UInt32] = []
    private weak var center: HotkeyCenter?

    fileprivate init(center: HotkeyCenter) {
        self.center = center
    }

    func unregister() {
        center?.unregister(self)
    }
}
