import Foundation
import Testing
import CommonCrypto
@testable import Susurro

/// Class fake so we can count synchronous calls from the actor adapter.
final class CountingKeychainAccessor: KeychainAccessor, @unchecked Sendable {
    private let password: Data
    private let errorToThrow: KeychainAccessError?
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }

    init(password: Data, error: KeychainAccessError? = nil) {
        self.password = password
        self.errorToThrow = error
    }

    func encryptionKeyData(service: String, account: String) throws -> Data {
        lock.lock()
        _callCount += 1
        lock.unlock()
        if let errorToThrow { throw errorToThrow }
        return password
    }
}

@Suite struct ChromiumCookieAdapterTests {

    /// Encrypt a plaintext the way Chromium does, given a password.
    private static func makeEncrypted(plaintext: String, key: Data) -> Data {
        let pt = Data(plaintext.utf8)
        var out = Data(count: pt.count + kCCBlockSizeAES128)
        var outLen: size_t = 0
        let iv = Array<UInt8>(repeating: 0x20, count: 16)
        let outCapacity = out.count
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

    @Test func decryptsCookieValuesEndToEnd() async throws {
        let password = Data("peanuts".utf8)
        let key = ChromiumCrypto.deriveAESKey(fromPassword: password)
        let authBlob = Self.makeEncrypted(plaintext: "abc123token", key: key)
        let ct0Blob = Self.makeEncrypted(plaintext: "csrfval", key: key)

        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in
            return [
                RawCookieRow(host: ".x.com", name: "auth_token", plaintextValue: "", encryptedValue: authBlob, path: "/", expiresUTC: 13_350_000_000_000_000, isSecure: true, isHTTPOnly: true),
                RawCookieRow(host: ".x.com", name: "ct0", plaintextValue: "", encryptedValue: ct0Blob, path: "/", expiresUTC: 13_350_000_000_000_000, isSecure: true, isHTTPOnly: false),
            ]
        }

        let fakeKC = CountingKeychainAccessor(password: password)
        let adapter = ChromiumCookieAdapter(source: .chrome, keychain: fakeKC, reader: fakeReader)

        // Won't actually exist on disk in test env, BUT adapter checks fileExists on the real Chrome path.
        // Skip hermetically when Chrome isn't installed.
        let chromePath = BrowserSource.chrome.cookiesDatabasePath.path
        guard FileManager.default.fileExists(atPath: chromePath) else { return }

        let cookies = try await adapter.cookies(forDomain: "x.com")
        #expect(cookies.count == 2)
        let auth = cookies.first { $0.name == "auth_token" }!
        #expect(auth.value == "abc123token")
        #expect(auth.isSecure == true)
        #expect(auth.isHTTPOnly == true)
    }

    @Test func cachesAESKeyAcrossCalls() async throws {
        // Skip if Chrome isn't installed — adapter checks real path.
        let chromePath = BrowserSource.chrome.cookiesDatabasePath.path
        guard FileManager.default.fileExists(atPath: chromePath) else { return }

        // Reader returns no rows, but adapter still calls keychain once to derive key.
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in [] }
        let fakeKC = CountingKeychainAccessor(password: Data("peanuts".utf8))

        let adapter = ChromiumCookieAdapter(source: .chrome, keychain: fakeKC, reader: fakeReader)
        _ = try? await adapter.cookies(forDomain: "x.com")
        _ = try? await adapter.cookies(forDomain: "x.com")
        #expect(fakeKC.callCount == 1)
    }

    @Test func databaseUnavailableWhenPathMissing() async {
        // Use Brave as a source whose cookies file is unlikely to exist in most dev envs.
        let bravePath = BrowserSource.brave.cookiesDatabasePath.path
        guard !FileManager.default.fileExists(atPath: bravePath) else { return }

        let fakeKC = CountingKeychainAccessor(password: Data())
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in [] }
        let adapter = ChromiumCookieAdapter(source: .brave, keychain: fakeKC, reader: fakeReader)

        do {
            _ = try await adapter.cookies(forDomain: "x.com")
            Issue.record("Expected throw")
        } catch let err as BrowserCookieError {
            #expect(err == .databaseUnavailable(.brave))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func keychainDeniedPropagatesAsBrowserCookieError() async {
        // Need Chrome installed so the fileExists guard passes.
        let chromePath = BrowserSource.chrome.cookiesDatabasePath.path
        guard FileManager.default.fileExists(atPath: chromePath) else { return }

        let fakeKC = CountingKeychainAccessor(password: Data(), error: .denied)
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in [] }
        let adapter = ChromiumCookieAdapter(source: .chrome, keychain: fakeKC, reader: fakeReader)

        do {
            _ = try await adapter.cookies(forDomain: "x.com")
            Issue.record("Expected throw")
        } catch let err as BrowserCookieError {
            #expect(err == .keychainDenied(.chrome))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
