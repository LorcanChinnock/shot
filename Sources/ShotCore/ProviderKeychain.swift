import Foundation
import Security

/// The API key for the provider, kept in the Keychain rather than in settings, which are plain files.
public enum ProviderKeychain {
    public static let service = "dev.lorcan.Shot.provider"
    private static let account = "api-key"

    private static func query(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// The saved key; empty when there is none.
    public static func load(service: String = service) -> String {
        var query = query(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves `key`; an empty one removes it. Returns whether it worked.
    @discardableResult
    public static func save(_ key: String, service: String = service) -> Bool {
        let query = query(service: service)
        guard !key.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(key.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess {
            return true
        }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
