import Foundation
import Security

enum Keychain {
    private static let service = "com.benatespina.susurro"

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            AppLogger.publishing.error("Keychain delete failed: OSStatus=\(deleteStatus, privacy: .public)")
        }

        if value.isEmpty { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLogger.publishing.error("Keychain add failed: OSStatus=\(addStatus, privacy: .public)")
        }
    }

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.publishing.error("Keychain copy failed: OSStatus=\(status, privacy: .public)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
