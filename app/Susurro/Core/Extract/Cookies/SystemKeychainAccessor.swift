import Foundation
import Security

struct SystemKeychainAccessor: KeychainAccessor {
    func encryptionKeyData(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainAccessError.unknown(status)
            }
            return data
        case errSecItemNotFound:
            throw KeychainAccessError.notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw KeychainAccessError.denied
        default:
            throw KeychainAccessError.unknown(status)
        }
    }
}
