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

/// The defaults `Setting` falls back to, worked out once.
@MainActor private let registeredDefaults = Preferences.defaults

/// A setting in a view, declared like `@AppStorage` but read from `SettingsStore`. `@Setting(key) var name: Type` takes
/// the default `Preferences` registers for `key`, so it's written in one place; an enum is stored as its raw value.
@MainActor
@propertyWrapper
struct Setting<Value> {
    private let key: String
    private let fallback: Value
    private let read: (Any?) -> Value?
    private let write: (Value) -> Any

    /// For a key with no registered default, such as a shortcut's.
    init(wrappedValue: Value, _ key: String) {
        self.key = key
        fallback = wrappedValue
        read = { $0 as? Value }
        write = { $0 }
    }

    /// For a key `Preferences.defaults` registers, which a test checks every such `@Setting` is.
    init(_ key: String) {
        guard let fallback = registeredDefaults[key] as? Value else {
            preconditionFailure("\(key) has no registered default of type \(Value.self)")
        }
        self.init(wrappedValue: fallback, key)
    }

    var wrappedValue: Value {
        get { read(SettingsStore.shared.value(forKey: key)) ?? fallback }
        nonmutating set { SettingsStore.shared.set(write(newValue), forKey: key) }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

extension Setting where Value: RawRepresentable, Value.RawValue == String {
    /// An enum stored as its raw value, falling back to the registered default when the stored one isn't a case.
    init(_ key: String) {
        guard let fallback = (registeredDefaults[key] as? String).flatMap(Value.init(rawValue:)) else {
            preconditionFailure("\(key) has no registered default that is a \(Value.self)")
        }
        self.key = key
        self.fallback = fallback
        read = { ($0 as? String).flatMap(Value.init(rawValue:)) }
        write = { $0.rawValue }
    }
}
