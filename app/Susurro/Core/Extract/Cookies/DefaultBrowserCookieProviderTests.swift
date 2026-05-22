import Foundation
import Testing
@testable import Susurro

@Suite struct DefaultBrowserCookieProviderTests {

    private static let validXCookies: [BrowserCookie] = [
        BrowserCookie(name: "auth_token", value: "tok", domain: ".x.com", path: "/", expiresUTC: 0, isSecure: true, isHTTPOnly: true),
        BrowserCookie(name: "ct0", value: "csrf", domain: ".x.com", path: "/", expiresUTC: 0, isSecure: true, isHTTPOnly: false),
        BrowserCookie(name: "guest_id", value: "g", domain: ".x.com", path: "/", expiresUTC: 0, isSecure: true, isHTTPOnly: false),
    ]

    private static let partialCookiesNoCT0: [BrowserCookie] = [
        BrowserCookie(name: "auth_token", value: "tok", domain: ".x.com", path: "/", expiresUTC: 0, isSecure: true, isHTTPOnly: true),
        BrowserCookie(name: "guest_id", value: "g", domain: ".x.com", path: "/", expiresUTC: 0, isSecure: true, isHTTPOnly: false),
    ]

    final class ConstantKeychain: KeychainAccessor, @unchecked Sendable {
        let password: Data
        init(password: Data) { self.password = password }
        func encryptionKeyData(service: String, account: String) throws -> Data { password }
    }

    /// Creates a hermetic stub adapter backed by a temp DB file — never touches real Chromium paths.
    private static func makeStubAdapter(cookies: [BrowserCookie], for source: BrowserSource) -> ChromiumCookieAdapter {
        let rows = cookies.map { c in
            RawCookieRow(
                host: c.domain, name: c.name, plaintextValue: c.value, encryptedValue: Data(),
                path: c.path, expiresUTC: c.expiresUTC, isSecure: c.isSecure, isHTTPOnly: c.isHTTPOnly
            )
        }
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in rows }
        let fakeKC = ConstantKeychain(password: Data("peanuts".utf8))

        // Create temp DB file (placeholder — reader is faked so content doesn't matter)
        let tmpDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("stub-\(source.rawValue)-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: tmpDB.path, contents: Data())

        return ChromiumCookieAdapter(
            source: source,
            keychain: fakeKC,
            reader: fakeReader,
            databaseURL: tmpDB
        )
    }

    @Test func defaultChromiumWinsWhenItHasSession() async throws {
        let adapterFactory: @Sendable (BrowserSource) -> ChromiumCookieAdapter = { source in
            Self.makeStubAdapter(cookies: Self.validXCookies, for: source)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .chrome },
            isSafariOnly: { false },
            installedBrowsers: { [.chrome] }
        )

        let cookies = try await provider.cookies(forDomain: "x.com")
        let names = Set(cookies.map(\.name))
        #expect(names.contains("auth_token"))
        #expect(names.contains("ct0"))
    }

    @Test func fallsBackWhenDefaultHasNoSession() async throws {
        // Default = arc has no session; chrome has session — provider should try chrome next.
        let adapterFactory: @Sendable (BrowserSource) -> ChromiumCookieAdapter = { source in
            if source == .arc {
                return Self.makeStubAdapter(cookies: Self.partialCookiesNoCT0, for: source)
            }
            return Self.makeStubAdapter(cookies: Self.validXCookies, for: source)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .arc },
            isSafariOnly: { false },
            installedBrowsers: { [.arc, .chrome] }
        )

        let cookies = try await provider.cookies(forDomain: "x.com")
        let names = Set(cookies.map(\.name))
        #expect(names.contains("auth_token"))
        #expect(names.contains("ct0"))
    }

    @Test func throwsOnlySafariDetectedWhenNoChromiumAndSafariDefault() async {
        let adapterFactory: @Sendable (BrowserSource) -> ChromiumCookieAdapter = { source in
            Self.makeStubAdapter(cookies: [], for: source)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data()),
            adapterFactory: adapterFactory,
            defaultBrowser: { nil },
            isSafariOnly: { true },
            installedBrowsers: { [] }
        )

        do {
            _ = try await provider.cookies(forDomain: "x.com")
            Issue.record("Expected throw")
        } catch let error as BrowserCookieError {
            #expect(error == .onlySafariDetected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func throwsNoBrowserWhenNothingInstalledAndDefaultIsntSafari() async {
        let adapterFactory: @Sendable (BrowserSource) -> ChromiumCookieAdapter = { source in
            Self.makeStubAdapter(cookies: [], for: source)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data()),
            adapterFactory: adapterFactory,
            defaultBrowser: { nil },
            isSafariOnly: { false },
            installedBrowsers: { [] }
        )

        do {
            _ = try await provider.cookies(forDomain: "x.com")
            Issue.record("Expected throw")
        } catch let error as BrowserCookieError {
            #expect(error == .noBrowserDetected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func throwsNoXSessionWhenAllInstalledLackPair() async {
        let adapterFactory: @Sendable (BrowserSource) -> ChromiumCookieAdapter = { source in
            Self.makeStubAdapter(cookies: Self.partialCookiesNoCT0, for: source)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .chrome },
            isSafariOnly: { false },
            installedBrowsers: { [.chrome, .arc] }
        )

        do {
            _ = try await provider.cookies(forDomain: "x.com")
            Issue.record("Expected throw")
        } catch let error as BrowserCookieError {
            if case .noXSessionCookies(_) = error {
                // OK
            } else {
                Issue.record("Expected .noXSessionCookies, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
