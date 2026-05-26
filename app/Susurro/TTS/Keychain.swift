import Foundation
import Security

enum Keychain {
    private static let service = "com.benatespina.susurro"

    // kSecUseDataProtectionKeychain requires the `keychain-access-groups` entitlement,
    // which is present only in the Debug entitlements file. The ad-hoc Release build
    // (Homebrew cask) intentionally omits restricted entitlements to pass AMFI, so in
    // Release we fall back to the standard file-based keychain, which needs no entitlement.
    private static func baseQuery(for account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if DEBUG
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)

        let query = baseQuery(for: account)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            AppLogger.publishing.error("Keychain delete failed: OSStatus=\(deleteStatus, privacy: .public)")
        }

        if value.isEmpty { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLogger.publishing.error("Keychain add failed: OSStatus=\(addStatus, privacy: .public)")
        }
    }

    static func string(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.publishing.error("Keychain copy failed: OSStatus=\(status, privacy: .public)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
