import Foundation
import CommonCrypto

enum ChromiumCryptoError: Error, Equatable {
    case inputTooShort
    case missingVersionPrefix
    case decryptionFailed
    case invalidUTF8
}

enum ChromiumCrypto {
    static let salt = "saltysalt"
    static let iterations: UInt32 = 1003
    static let keyLength = 16 // AES-128
    static let ivBytes = Array<UInt8>(repeating: 0x20, count: 16)

    /// PBKDF2-HMAC-SHA1 of password with Chromium's documented params.
    static func deriveAESKey(fromPassword password: Data) -> Data {
        var derived = Data(count: keyLength)
        let saltBytes = Array(salt.utf8)
        _ = derived.withUnsafeMutableBytes { derivedPtr in
            password.withUnsafeBytes { passwordPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                    password.count,
                    saltBytes,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    iterations,
                    derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    keyLength
                )
            }
        }
        return derived
    }

    /// Decrypt an `encrypted_value` byte blob into a UTF-8 string.
    /// Handles `v10` / `v11` prefix and optional SHA-256 plaintext prefix (Chrome >=130).
    static func decrypt(encryptedValue: Data, key: Data) throws -> String {
        // Must have at least 3-byte version prefix + 16-byte IV-worth of ciphertext.
        guard encryptedValue.count > 3 else { throw ChromiumCryptoError.inputTooShort }
        let prefix = encryptedValue.prefix(3)
        guard prefix == Data("v10".utf8) || prefix == Data("v11".utf8) else {
            throw ChromiumCryptoError.missingVersionPrefix
        }
        let ciphertext = encryptedValue.dropFirst(3)
        guard ciphertext.count >= 16, ciphertext.count % 16 == 0 else {
            throw ChromiumCryptoError.inputTooShort
        }

        let outBufferSize = ciphertext.count + kCCBlockSizeAES128
        var outBuffer = Data(count: outBufferSize)
        var outLength: size_t = 0

        let status: CCCryptorStatus = outBuffer.withUnsafeMutableBytes { outPtr in
            key.withUnsafeBytes { keyPtr in
                ciphertext.withUnsafeBytes { ctPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, keyLength,
                        ivBytes,
                        ctPtr.baseAddress, ciphertext.count,
                        outPtr.baseAddress, outBufferSize,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ChromiumCryptoError.decryptionFailed }
        outBuffer.count = outLength

        // Strip optional 32-byte SHA-256 plaintext prefix used by Chrome >=130.
        // Heuristic: if total length > 32 AND the first 32 bytes contain any non-ASCII-printable byte
        // (likely a SHA digest), drop them.
        let stripped: Data
        if outBuffer.count > 32 {
            let first32 = outBuffer.prefix(32)
            let allPrintable = first32.allSatisfy { byte in
                (0x20...0x7E).contains(byte) || byte == 0x09 || byte == 0x0A || byte == 0x0D
            }
            stripped = allPrintable ? outBuffer : outBuffer.dropFirst(32)
        } else {
            stripped = outBuffer
        }

        guard let str = String(data: stripped, encoding: .utf8) else {
            throw ChromiumCryptoError.invalidUTF8
        }
        return str
    }
}
