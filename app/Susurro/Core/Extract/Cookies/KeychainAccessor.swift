import Foundation

protocol KeychainAccessor: Sendable {
    func encryptionKeyData(service: String, account: String) throws -> Data
}

enum KeychainAccessError: Error, Equatable {
    case denied
    case notFound
    case unknown(OSStatus)
}
