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

    /// Creates a temporary placeholder SQLite file and returns its URL.
    private static func makeTempDB(label: String = UUID().uuidString) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChromiumAdapterTest-\(label).sqlite")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
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
        let tmpDB = Self.makeTempDB(label: "decrypt")
        let adapter = ChromiumCookieAdapter(source: .chrome, keychain: fakeKC, reader: fakeReader, databaseURL: tmpDB)

        let cookies = try await adapter.cookies(forDomain: "x.com")
        #expect(cookies.count == 2)
        let auth = cookies.first { $0.name == "auth_token" }!
        #expect(auth.value == "abc123token")
        #expect(auth.isSecure == true)
        #expect(auth.isHTTPOnly == true)
    }

    @Test func cachesAESKeyAcrossCalls() async throws {
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in [] }
        let fakeKC = CountingKeychainAccessor(password: Data("peanuts".utf8))
        let tmpDB = Self.makeTempDB(label: "cache")
        let adapter = ChromiumCookieAdapter(source: .chrome, keychain: fakeKC, reader: fakeReader, databaseURL: tmpDB)
        _ = try? await adapter.cookies(forDomain: "x.com")
        _ = try? await adapter.cookies(forDomain: "x.com")
        #expect(fakeKC.callCount == 1)
    }

    @Test func databaseUnavailableWhenPathMissing() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-db-\(UUID().uuidString).sqlite")

        let fakeKC = CountingKeychainAccessor(password: Data())
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in [] }
        let adapter = ChromiumCookieAdapter(source: .brave, keychain: fakeKC, reader: fakeReader, databaseURL: missingURL)

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
        let fakeKC = CountingKeychainAccessor(password: Data(), error: .denied)
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in [] }
        let tmpDB = Self.makeTempDB(label: "keychain-denied")
        let adapter = ChromiumCookieAdapter(source: .chrome, keychain: fakeKC, reader: fakeReader, databaseURL: tmpDB)

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
