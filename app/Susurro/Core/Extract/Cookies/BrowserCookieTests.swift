import Foundation
import Testing
@testable import Susurro

@Suite struct BrowserCookieTests {
    @Test func webkitEpochConversion() {
        // 13_350_000_000_000_000 microseconds = 1601 + ~423 years = ~2024
        let cookie = BrowserCookie(
            name: "test", value: "v", domain: ".x.com", path: "/",
            expiresUTC: 13_350_000_000_000_000,
            isSecure: true, isHTTPOnly: true
        )
        let http = cookie.toHTTPCookie()
        #expect(http != nil)
        let expectedSeconds = Double(13_350_000_000_000_000 / 1_000_000) - 11_644_473_600
        let actualSeconds = http!.expiresDate!.timeIntervalSince1970
        #expect(abs(actualSeconds - expectedSeconds) < 1.0)
    }

    @Test func sessionCookieNoExpiry() {
        let cookie = BrowserCookie(
            name: "sess", value: "v", domain: ".x.com", path: "/",
            expiresUTC: 0,
            isSecure: false, isHTTPOnly: false
        )
        let http = cookie.toHTTPCookie()
        #expect(http != nil)
        // Session cookies: expiresDate should be nil
        #expect(http!.expiresDate == nil)
    }

    @Test func secureFlagPreserved() {
        let cookie = BrowserCookie(
            name: "auth_token", value: "abc", domain: ".x.com", path: "/",
            expiresUTC: 13_350_000_000_000_000,
            isSecure: true, isHTTPOnly: true
        )
        let http = cookie.toHTTPCookie()
        #expect(http != nil)
        #expect(http!.isSecure == true)
        #expect(http!.isHTTPOnly == true)
    }

    @Test func browserSourceConfigurations() {
        #expect(BrowserSource.allCases.count == 4)
        for source in BrowserSource.allCases {
            #expect(!source.displayName.isEmpty)
            #expect(!source.bundleIdentifier.isEmpty)
            #expect(source.cookiesDatabasePath.path.contains(NSHomeDirectory()))
        }
        #expect(BrowserSource.edge.keychainService == "Microsoft Edge Safe Storage")
        #expect(BrowserSource.chrome.keychainService == "Chrome Safe Storage")
        #expect(BrowserSource.arc.keychainService == "Chrome Safe Storage")
        #expect(BrowserSource.brave.keychainService == "Chrome Safe Storage")
    }
}
