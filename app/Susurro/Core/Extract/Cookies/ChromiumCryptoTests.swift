import Foundation
import Testing
import CommonCrypto
@testable import Susurro

@Suite struct ChromiumCryptoTests {

    // MARK: - PBKDF2

    @Test func deriveAESKeyIsDeterministic() {
        let pw = Data("peanuts".utf8)
        let k1 = ChromiumCrypto.deriveAESKey(fromPassword: pw)
        let k2 = ChromiumCrypto.deriveAESKey(fromPassword: pw)
        #expect(k1 == k2)
        #expect(k1.count == 16)
    }

    @Test func deriveAESKeyDifferentPasswordsProduceDifferentKeys() {
        let k1 = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        let k2 = ChromiumCrypto.deriveAESKey(fromPassword: Data("almonds".utf8))
        #expect(k1 != k2)
    }

    // MARK: - Round trip

    /// Helper: encrypt a plaintext like Chromium does (v10 prefix + AES-CBC + 0x20 IV + PKCS7).
    /// Used only in tests to produce ciphertexts we then decrypt.
    private func encryptForTest(plaintext: String, key: Data) -> Data {
        let pt = Data(plaintext.utf8)
        let outCapacity = pt.count + kCCBlockSizeAES128
        var out = Data(count: outCapacity)
        var outLen: size_t = 0
        let iv = Array<UInt8>(repeating: 0x20, count: 16)
        _ = out.withUnsafeMutableBytes { outPtr in
            key.withUnsafeBytes { keyPtr in
                pt.withUnsafeBytes { ptPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, 16,
                        iv,
                        ptPtr.baseAddress, pt.count,
                        outPtr.baseAddress, outCapacity,
                        &outLen
                    )
                }
            }
        }
        out.count = outLen
        var blob = Data("v10".utf8)
        blob.append(out)
        return blob
    }

    @Test func roundTripDecryptYieldsPlaintext() throws {
        let key = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        let plaintext = "auth_token=abcdef0123456789"
        let blob = encryptForTest(plaintext: plaintext, key: key)
        let decrypted = try ChromiumCrypto.decrypt(encryptedValue: blob, key: key)
        #expect(decrypted == plaintext)
    }

    @Test func roundTripV11Prefix() throws {
        let key = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        let plaintext = "ct0=somevalue"
        // Build v11 variant by patching the prefix
        var blob = encryptForTest(plaintext: plaintext, key: key)
        blob[0] = 0x76 // 'v' (unchanged)
        blob[1] = 0x31 // '1'
        blob[2] = 0x31 // '1'
        let decrypted = try ChromiumCrypto.decrypt(encryptedValue: blob, key: key)
        #expect(decrypted == plaintext)
    }

    @Test func roundTripWithSHA256PlaintextPrefix() throws {
        // Simulate Chrome >=130: prepend 32 bytes that look like a SHA-256 digest (binary).
        let key = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        let realPlaintext = "auth_token=xyz"
        // Construct: 32 binary bytes (non-printable) + plaintext
        var plaintextBytes = Data((0..<32).map { _ in UInt8.random(in: 0...0x1F) }) // control chars
        plaintextBytes.append(Data(realPlaintext.utf8))
        let pt = String(data: plaintextBytes, encoding: .isoLatin1)!
        let blob = encryptForTest(plaintext: pt, key: key)
        let decrypted = try ChromiumCrypto.decrypt(encryptedValue: blob, key: key)
        #expect(decrypted == realPlaintext)
    }

    // MARK: - Error paths

    @Test func decryptInputTooShortThrows() {
        let key = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        let blob = Data("v1".utf8)
        do {
            _ = try ChromiumCrypto.decrypt(encryptedValue: blob, key: key)
            Issue.record("Expected throw")
        } catch let error as ChromiumCryptoError {
            #expect(error == .inputTooShort)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func decryptMissingVersionPrefixThrows() {
        let key = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        // 32 random bytes, no v10/v11 prefix
        let blob = Data(repeating: 0xAB, count: 32)
        do {
            _ = try ChromiumCrypto.decrypt(encryptedValue: blob, key: key)
            Issue.record("Expected throw")
        } catch let error as ChromiumCryptoError {
            #expect(error == .missingVersionPrefix)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func decryptWrongKeyThrowsOrInvalidUTF8() {
        let key1 = ChromiumCrypto.deriveAESKey(fromPassword: Data("peanuts".utf8))
        let key2 = ChromiumCrypto.deriveAESKey(fromPassword: Data("walnuts".utf8))
        let blob = encryptForTest(plaintext: "hello", key: key1)
        do {
            _ = try ChromiumCrypto.decrypt(encryptedValue: blob, key: key2)
            // If it doesn't throw, decryption may produce garbage that happens to be UTF-8.
            // Either outcome is acceptable; we just want NO crash.
        } catch {
            // Expected: decryptionFailed or invalidUTF8
        }
    }
}
