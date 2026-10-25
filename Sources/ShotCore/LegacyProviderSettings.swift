import Foundation
import Security

/// What the removed "use my own AI provider" setting left behind: its preferences and its API key in the Keychain.
/// Run once at launch, so a key you pasted doesn't stay in the Keychain with nothing to use it.
public enum LegacyProviderSettings {
    static let keys = ["provider", "providerPreset", "providerBaseURL", "providerModel", "providerFormat"]
    public static let keychainService = "dev.lorcan.Shot.provider"

    public static func remove(from store: UserDefaults = .standard, keychainService: String = keychainService) {
        for key in keys {
            store.removeObject(forKey: key)
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "api-key"]
        SecItemDelete(query as CFDictionary)
    }
}
