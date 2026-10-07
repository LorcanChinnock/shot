import ShotCore
import SwiftUI

/// The settings every view reads, refreshed in the same update as any write to the defaults. `@AppStorage` catches up an
/// update later, so a view combining it with other state could briefly show a combination that never existed.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private var values: [String: Any] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
        // Posted on the writing thread before the write returns, so writes from the main thread land in the same update.
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: nil) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.reload() }
            } else {
                Task { @MainActor in self?.reload() }
            }
        })
        // Other processes, such as `defaults write`, don't post that notification here.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
    }

    func value(forKey key: String) -> Any? {
        values[key]
    }

    func set(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private func reload() {
        var fresh: [String: Any] = [:]
        for key in Preferences.defaults.keys {
            fresh[key] = defaults.object(forKey: key)
        }
        // Unrelated writes, such as window positions, shouldn't redraw every settings view.
        if !(fresh as NSDictionary).isEqual(to: values) {
            values = fresh
        }
    }
}

/// A setting in a view, declared like `@AppStorage` but read from `SettingsStore`.
@MainActor
@propertyWrapper
struct Setting<Value> {
    private let key: String
    private let fallback: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        fallback = wrappedValue
    }

    var wrappedValue: Value {
        get { SettingsStore.shared.value(forKey: key) as? Value ?? fallback }
        nonmutating set { SettingsStore.shared.set(newValue, forKey: key) }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
