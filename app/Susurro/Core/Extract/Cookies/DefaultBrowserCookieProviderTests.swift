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
    private static func makeStubAdapter(cookies: [BrowserCookie], for source: BrowserSource, url: URL? = nil) -> ChromiumCookieAdapter {
        let rows = cookies.map { c in
            RawCookieRow(
                host: c.domain, name: c.name, plaintextValue: c.value, encryptedValue: Data(),
                path: c.path, expiresUTC: c.expiresUTC, isSecure: c.isSecure, isHTTPOnly: c.isHTTPOnly
            )
        }
        let fakeReader: @Sendable (URL, [String]) throws -> [RawCookieRow] = { _, _ in rows }
        let fakeKC = ConstantKeychain(password: Data("peanuts".utf8))

        // Create temp DB file (placeholder — reader is faked so content doesn't matter)
        let tmpDB = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("stub-\(source.rawValue)-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: tmpDB.path, contents: Data())

        return ChromiumCookieAdapter(
            source: source,
            keychain: fakeKC,
            reader: fakeReader,
            databaseURL: tmpDB
        )
    }

    /// One profile per browser, factory ignores URL — previous behaviour unchanged.
    private static func singleProfilePaths(for source: BrowserSource) -> [URL] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-\(source.rawValue)-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: tmp.path, contents: Data())
        return [tmp]
    }

    @Test func defaultChromiumWinsWhenItHasSession() async throws {
        let adapterFactory: @Sendable (BrowserSource, URL) -> ChromiumCookieAdapter = { source, url in
            Self.makeStubAdapter(cookies: Self.validXCookies, for: source, url: url)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .chrome },
            isSafariOnly: { false },
            installedBrowsers: { [.chrome] },
            profilePaths: { Self.singleProfilePaths(for: $0) }
        )

        let cookies = try await provider.cookies(forDomain: "x.com")
        let names = Set(cookies.map(\.name))
        #expect(names.contains("auth_token"))
        #expect(names.contains("ct0"))
    }

    @Test func fallsBackWhenDefaultHasNoSession() async throws {
        // Default = arc has no session; chrome has session — provider should try chrome next.
        let adapterFactory: @Sendable (BrowserSource, URL) -> ChromiumCookieAdapter = { source, url in
            if source == .arc {
                return Self.makeStubAdapter(cookies: Self.partialCookiesNoCT0, for: source, url: url)
            }
            return Self.makeStubAdapter(cookies: Self.validXCookies, for: source, url: url)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .arc },
            isSafariOnly: { false },
            installedBrowsers: { [.arc, .chrome] },
            profilePaths: { Self.singleProfilePaths(for: $0) }
        )

        let cookies = try await provider.cookies(forDomain: "x.com")
        let names = Set(cookies.map(\.name))
        #expect(names.contains("auth_token"))
        #expect(names.contains("ct0"))
    }

    @Test func throwsOnlySafariDetectedWhenNoChromiumAndSafariDefault() async {
        let adapterFactory: @Sendable (BrowserSource, URL) -> ChromiumCookieAdapter = { source, url in
            Self.makeStubAdapter(cookies: [], for: source, url: url)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data()),
            adapterFactory: adapterFactory,
            defaultBrowser: { nil },
            isSafariOnly: { true },
            installedBrowsers: { [] },
            profilePaths: { _ in [] }
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
        let adapterFactory: @Sendable (BrowserSource, URL) -> ChromiumCookieAdapter = { source, url in
            Self.makeStubAdapter(cookies: [], for: source, url: url)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data()),
            adapterFactory: adapterFactory,
            defaultBrowser: { nil },
            isSafariOnly: { false },
            installedBrowsers: { [] },
            profilePaths: { _ in [] }
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
        let adapterFactory: @Sendable (BrowserSource, URL) -> ChromiumCookieAdapter = { source, url in
            Self.makeStubAdapter(cookies: Self.partialCookiesNoCT0, for: source, url: url)
        }
        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .chrome },
            isSafariOnly: { false },
            installedBrowsers: { [.chrome, .arc] },
            profilePaths: { Self.singleProfilePaths(for: $0) }
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

    @Test func picksSecondProfileWhenDefaultProfileLacksSession() async throws {
        // Simulates: Chrome Default has no session, Profile 2 has auth_token+ct0.
        // The provider should iterate both paths and return the cookies from Profile 2.
        let defaultProfileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrome-default-\(UUID().uuidString).sqlite")
        let profile2URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrome-profile2-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: defaultProfileURL.path, contents: Data())
        FileManager.default.createFile(atPath: profile2URL.path, contents: Data())

        let adapterFactory: @Sendable (BrowserSource, URL) -> ChromiumCookieAdapter = { source, url in
            if url == profile2URL {
                return Self.makeStubAdapter(cookies: Self.validXCookies, for: source, url: url)
            }
            // Default profile and any other path return partial cookies (no ct0)
            return Self.makeStubAdapter(cookies: Self.partialCookiesNoCT0, for: source, url: url)
        }

        let provider = DefaultBrowserCookieProvider(
            keychain: ConstantKeychain(password: Data("peanuts".utf8)),
            adapterFactory: adapterFactory,
            defaultBrowser: { .chrome },
            isSafariOnly: { false },
            installedBrowsers: { [.chrome] },
            profilePaths: { _ in [defaultProfileURL, profile2URL] }
        )

        let cookies = try await provider.cookies(forDomain: "x.com")
        let names = Set(cookies.map(\.name))
        #expect(names.contains("auth_token"))
        #expect(names.contains("ct0"))
        #expect(names.contains("guest_id"))
    }
}
