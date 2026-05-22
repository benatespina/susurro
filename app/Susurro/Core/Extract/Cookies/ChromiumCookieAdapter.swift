import Foundation
import os.log

actor ChromiumCookieAdapter {
    private let source: BrowserSource
    private let keychain: any KeychainAccessor
    private let reader: @Sendable (URL, [String]) throws -> [RawCookieRow]
    private var cachedKey: Data?
    private let logger = Logger(subsystem: "com.benatespina.susurro", category: "ChromiumCookieAdapter")

    init(
        source: BrowserSource,
        keychain: any KeychainAccessor,
        reader: @escaping @Sendable (URL, [String]) throws -> [RawCookieRow] = SQLiteCookieReader.readCookies
    ) {
        self.source = source
        self.keychain = keychain
        self.reader = reader
    }

    /// Returns decrypted X session cookies (`*.x.com` and `*.twitter.com`).
    /// `domain` is currently informational — the SQL filter is hardcoded to X domains.
    func cookies(forDomain domain: String) async throws -> [BrowserCookie] {
        let dbURL = source.cookiesDatabasePath
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw BrowserCookieError.databaseUnavailable(source)
        }

        let key = try resolveKey()

        let rows: [RawCookieRow]
        do {
            rows = try reader(dbURL, ["%.x.com", "%.twitter.com"])
        } catch {
            throw BrowserCookieError.databaseUnavailable(source)
        }

        var cookies: [BrowserCookie] = []
        for row in rows {
            let value: String
            if !row.encryptedValue.isEmpty {
                do {
                    value = try ChromiumCrypto.decrypt(encryptedValue: row.encryptedValue, key: key)
                } catch {
                    logger.warning("Decrypt failed for \(row.host, privacy: .public)/\(row.name, privacy: .public): \(String(describing: error))")
                    continue // skip this row, don't abort batch
                }
            } else {
                value = row.plaintextValue
            }

            cookies.append(BrowserCookie(
                name: row.name,
                value: value,
                domain: row.host,
                path: row.path,
                expiresUTC: row.expiresUTC,
                isSecure: row.isSecure,
                isHTTPOnly: row.isHTTPOnly
            ))
        }
        return cookies
    }

    private func resolveKey() throws -> Data {
        if let cachedKey { return cachedKey }
        let password: Data
        do {
            password = try keychain.encryptionKeyData(service: source.keychainService, account: source.keychainAccount)
        } catch KeychainAccessError.denied {
            throw BrowserCookieError.keychainDenied(source)
        } catch KeychainAccessError.notFound {
            throw BrowserCookieError.keychainNotFound(source)
        } catch {
            throw BrowserCookieError.keychainDenied(source) // unknown OSStatus treated as denied
        }
        let derived = ChromiumCrypto.deriveAESKey(fromPassword: password)
        cachedKey = derived
        return derived
    }
}
