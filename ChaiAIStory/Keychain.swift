import Foundation
import Security

enum Keychain {
    private static let service = "com.kongdean.ChaiAIStory.openai"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "byok", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "byok"]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, rhs in rhs }) as CFDictionary, nil) == errSecSuccess else { throw NSError(domain: "Keychain", code: Int(status)) }
        } else if status != errSecSuccess { throw NSError(domain: "Keychain", code: Int(status)) }
    }
}
