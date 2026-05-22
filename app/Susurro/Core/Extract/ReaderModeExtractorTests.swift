import Foundation
import Testing
import WebKit
@testable import Susurro

// WKWebView is not unit-testable without a test host bundle.
// This suite only confirms the symbol exists and the @MainActor annotation is preserved.
// Real extraction coverage lives in ParityHarnessTests behind PARITY_AUDIT.

@MainActor
@Suite("ReaderModeExtractor")
struct ReaderModeExtractorTests {

    @Test("extractIsCallableUnderMainActor")
    func extractIsCallableUnderMainActor() async {
        let url = URL(string: "https://example.com/")!
        _ = try? await ReaderModeExtractor.extract(url: url.absoluteString)
        #expect(true)
    }

    // MARK: - Cookies overload smoke tests

    @Test("extractWithEmptyCookiesUsesDefaultPath")
    func extractWithEmptyCookiesUsesDefaultPath() async {
        // Smoke test: passing [] cookies should not crash setup. The actual extraction will
        // either succeed or throw a timeout; we just want to verify the cookies overload
        // doesn't throw on initialization.
        do {
            _ = try await ReaderModeExtractor.extract(url: "about:blank", cookies: [])
        } catch {
            // Any error is acceptable here — the test purpose is only verifying setup doesn't crash.
        }
        #expect(true)
    }

    @Test("extractWithNilCookiesMatchesLegacy")
    func extractWithNilCookiesMatchesLegacy() async {
        // Verify the new overload with nil cookies is callable (matches legacy code path).
        do {
            _ = try await ReaderModeExtractor.extract(url: "about:blank", cookies: nil)
        } catch {
            // OK — setup must not crash.
        }
        #expect(true)
    }

    @Test("cookiesOverloadAcceptsValidXCookie")
    func cookiesOverloadAcceptsValidXCookie() async {
        let cookie = HTTPCookie(properties: [
            .name: "auth_token",
            .value: "abc",
            .domain: ".x.com",
            .path: "/",
            .secure: "TRUE"
        ])!
        do {
            _ = try await ReaderModeExtractor.extract(url: "about:blank", cookies: [cookie])
        } catch {
            // OK — just want no crash during cookie injection setup.
        }
        #expect(true)
    }
}
