import Foundation
import Security

/// Minimal Keychain wrapper for small Codable values (auth tokens).
enum Keychain {
    private static var service: String { Bundle.main.bundleIdentifier ?? "app" }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T, key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        SecItemDelete(baseQuery(key: key) as CFDictionary)
        var attributes = baseQuery(key: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }
}
