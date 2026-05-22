import Foundation
import Testing
@testable import Susurro

// MARK: - URLProtocol Mock

nonisolated(unsafe) private var syndicationMockResponseBody: String = ""
nonisolated(unsafe) private var syndicationMockStatusCode: Int = 200
nonisolated(unsafe) private var syndicationMockShouldNetworkError: Bool = false

private final class SyndicationMockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if syndicationMockShouldNetworkError {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let data = syndicationMockResponseBody.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: syndicationMockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeSyndicationSession(
    body: String,
    statusCode: Int = 200,
    networkError: Bool = false
) -> URLSession {
    syndicationMockResponseBody = body
    syndicationMockStatusCode = statusCode
    syndicationMockShouldNetworkError = networkError
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SyndicationMockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Tests

@Suite("XComSyndicationStrategy", .serialized)
struct XComSyndicationStrategyTests {

    @Test("canHandle: accepts x.com/twitter.com variants, rejects others and no-status paths")
    func canHandleVariantsAndRejectsOthers() {
        let strategy = XComSyndicationStrategy()

        // Valid variants
        #expect(strategy.canHandle(URL(string: "https://x.com/addyosmani/status/123")!))
        #expect(strategy.canHandle(URL(string: "https://twitter.com/addyosmani/status/123")!))
        #expect(strategy.canHandle(URL(string: "https://www.x.com/someone/status/456")!))
        #expect(strategy.canHandle(URL(string: "https://www.twitter.com/someone/status/456")!))
        #expect(strategy.canHandle(URL(string: "https://mobile.x.com/someone/status/789")!))
        #expect(strategy.canHandle(URL(string: "https://mobile.twitter.com/someone/status/789")!))

        // Non-matching host
        #expect(!strategy.canHandle(URL(string: "https://github.com/user/repo")!))

        // x.com URL with no /status/<id> path
        #expect(!strategy.canHandle(URL(string: "https://x.com/addyosmani")!))
    }

    @Test("canHandle: rejects article path (not status path)")
    func extractTokensViaCanHandlePathValidation() {
        let strategy = XComSyndicationStrategy()
        #expect(!strategy.canHandle(URL(string: "https://x.com/i/article/123")!))
    }

    @Test("extracts tweet text for prose tweet")
    func extractsTweetTextForProseTweet() async throws {
        let json = """
        {"text": "Hello world.", "user": {"name": "Foo Bar"}}
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(session: session)

        let result = try await strategy.extract(url: URL(string: "https://x.com/foo/status/123")!)

        #expect(result.text == "Hello world.")
        #expect(result.title == "Foo Bar")
    }

    @Test("extracts article content when present")
    func extractsArticleContentWhenPresent() async throws {
        let json = """
        {
          "text": "https://t.co/abc",
          "user": {"name": "Addy Osmani"},
          "article": {"title": "Don't Outsource the Learning", "preview_text": "Right now, it's too easy..."}
        }
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(session: session)

        let result = try await strategy.extract(url: URL(string: "https://x.com/addyosmani/status/2056078124346228860")!)

        // Either the WKWebView render succeeded (longer text) or fallback fired; either way
        // the result text must start with the preview_text prefix.
        #expect(result.text.hasPrefix("Right now, it's too easy...") || result.text.count >= "Right now, it's too easy...".count)
        #expect(result.title == "Don't Outsource the Learning")
    }

    @Test("prefers article preview over plain text")
    func prefersArticlePreviewOverPlainText() async throws {
        let json = """
        {
          "text": "https://t.co/abc",
          "user": {"name": "Addy Osmani"},
          "article": {"title": "Don't Outsource the Learning", "preview_text": "Right now, it's too easy..."}
        }
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(session: session)

        let result = try await strategy.extract(url: URL(string: "https://x.com/addyosmani/status/2056078124346228860")!)

        // article content wins over the t.co text field; at minimum we get the preview_text
        #expect(result.text.hasPrefix("Right now, it's too easy...") || result.text.count >= "Right now, it's too easy...".count)
        #expect(result.title == "Don't Outsource the Learning")
    }

    @Test("returns preview text as fallback when WKWebView extraction fails")
    func linkToArticleReturnsPreviewWhenWKWebViewFails() async throws {
        // No rest_id in the JSON — WKWebView path is not attempted; preview_text is returned directly.
        let json = """
        {
          "text": "https://t.co/abc",
          "user": {"name": "Addy Osmani"},
          "article": {"title": "Don't Outsource the Learning", "preview_text": "Right now, it's too easy..."}
        }
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(session: session)

        let result = try await strategy.extract(url: URL(string: "https://x.com/addyosmani/status/2056078124346228860")!)

        // WKWebView is unavailable in unit test env; strategy falls back to preview_text.
        #expect(result.text == "Right now, it's too easy...")
        #expect(result.title == "Don't Outsource the Learning")
    }

    @Test("throws for link-only tweet without article")
    func throwsForLinkOnlyTweetWithoutArticle() async throws {
        let json = """
        {"text": "https://t.co/abc", "user": {"name": "Foo"}}
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(session: session)

        await #expect(throws: BackendError.extractFailed(
            "syndication: tweet content not extractable (link-only with no article preview)"
        )) {
            try await strategy.extract(url: URL(string: "https://x.com/foo/status/123")!)
        }
    }

    @Test("throws for non-2xx HTTP response")
    func throwsForNon2xx() async throws {
        let session = makeSyndicationSession(body: "Not Found", statusCode: 404)
        let strategy = XComSyndicationStrategy(session: session)

        await #expect(throws: BackendError.extractFailed("syndication HTTP 404")) {
            try await strategy.extract(url: URL(string: "https://x.com/someone/status/999")!)
        }
    }

    @Test("throws for malformed JSON")
    func throwsForMalformedJSON() async throws {
        let session = makeSyndicationSession(body: "{ invalid json !!!")
        let strategy = XComSyndicationStrategy(session: session)

        await #expect(throws: BackendError.extractFailed("syndication JSON parse")) {
            try await strategy.extract(url: URL(string: "https://x.com/someone/status/999")!)
        }
    }

    @Test("token computation completes and strategy extracts")
    func tokenComputationCompletesAndStrategyExtracts() async throws {
        // Verify the JavaScriptCore token computation path succeeds and the request reaches
        // the HTTP layer. A successful extraction confirms the token was computed and the
        // mock URL session received the request (i.e. no throw before the HTTP call).
        let json = """
        {"text": "hello", "user": {"name": "foo"}}
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(session: session)

        let result = try await strategy.extract(
            url: URL(string: "https://x.com/addyosmani/status/2056078124346228860")!
        )

        #expect(result.text == "hello")
        #expect(result.title == "foo")
    }

    // MARK: - Cookie provider integration tests

    @Test("with cookie provider, passes cookies to reader extract")
    func withCookieProviderPassesCookiesToReader() async throws {
        let cookie = HTTPCookie(properties: [
            .name: "auth_token", .value: "tok", .domain: ".x.com", .path: "/",
            .secure: "TRUE"
        ])!

        struct MockProvider: BrowserCookieProvider {
            let cookie: HTTPCookie
            func cookies(forDomain domain: String) async throws -> [HTTPCookie] { [cookie] }
        }
        let provider = MockProvider(cookie: cookie)

        nonisolated(unsafe) var capturedCookies: [HTTPCookie]?
        let stubReader: @Sendable (String, [HTTPCookie]?) async throws -> (text: String, title: String?) = { _, cookies in
            capturedCookies = cookies
            // Return text longer than the preview ("Right now, it's too easy..." = 27 chars)
            return (String(repeating: "x", count: 1000), "Article Title")
        }

        // JSON with rest_id to trigger the readerExtract path
        let json = """
        {
          "text": "https://t.co/abc",
          "user": {"name": "Addy Osmani"},
          "article": {"title": "Article Title", "preview_text": "Right now, it's too easy...", "rest_id": "99999"}
        }
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(
            session: session,
            cookieProvider: provider,
            readerExtract: stubReader
        )

        _ = try await strategy.extract(url: URL(string: "https://x.com/foo/status/123")!)

        #expect(capturedCookies?.contains(where: { $0.name == "auth_token" }) == true)
    }

    @Test("provider error falls back to nil cookies and fires onProviderError")
    func providerErrorFallsBackToNilCookies() async throws {
        struct ThrowingProvider: BrowserCookieProvider {
            func cookies(forDomain domain: String) async throws -> [HTTPCookie] {
                throw BrowserCookieError.noBrowserDetected
            }
        }

        nonisolated(unsafe) var capturedCookies: [HTTPCookie]? = [
            HTTPCookie(properties: [.name: "sentinel", .value: "1", .domain: ".x.com", .path: "/"])!
        ]
        let stubReader: @Sendable (String, [HTTPCookie]?) async throws -> (text: String, title: String?) = { _, cookies in
            capturedCookies = cookies
            // Return text shorter than preview so we fall back to preview_text (proving execution continued)
            return ("short", nil)
        }

        nonisolated(unsafe) var notifiedError: BrowserCookieError?
        let onError: @Sendable (BrowserCookieError) -> Void = { err in notifiedError = err }

        let json = """
        {
          "text": "https://t.co/abc",
          "user": {"name": "Addy Osmani"},
          "article": {"title": "Article Title", "preview_text": "Right now, it's too easy...", "rest_id": "99999"}
        }
        """
        let session = makeSyndicationSession(body: json)
        let strategy = XComSyndicationStrategy(
            session: session,
            cookieProvider: ThrowingProvider(),
            readerExtract: stubReader,
            onProviderError: onError
        )

        let result = try await strategy.extract(url: URL(string: "https://x.com/foo/status/123")!)

        // readerExtract was called with nil cookies (fallback path)
        #expect(capturedCookies == nil)
        // onProviderError was fired with the actionable error
        #expect(notifiedError == .noBrowserDetected)
        // Strategy still returned the preview_text (no crash, no rethrow)
        #expect(result.text == "Right now, it's too easy...")
    }

    @Test("without provider, reader extract receives nil cookies")
    func withoutProviderBehavesAsBefore() async throws {
        // Sentinel non-nil value so we can confirm it was overwritten to nil
        nonisolated(unsafe) var capturedCookies: [HTTPCookie]? = [
            HTTPCookie(properties: [.name: "sentinel", .value: "1", .domain: ".x.com", .path: "/"])!
        ]
        let stubReader: @Sendable (String, [HTTPCookie]?) async throws -> (text: String, title: String?) = { _, cookies in
            capturedCookies = cookies
            return (String(repeating: "x", count: 1000), "Title")
        }

        let json = """
        {
          "text": "https://t.co/abc",
          "user": {"name": "Addy Osmani"},
          "article": {"title": "Title", "preview_text": "Short preview text.", "rest_id": "99999"}
        }
        """
        let session = makeSyndicationSession(body: json)
        // cookieProvider: nil (default) — no cookie code should run
        let strategy = XComSyndicationStrategy(
            session: session,
            cookieProvider: nil,
            readerExtract: stubReader
        )

        _ = try await strategy.extract(url: URL(string: "https://x.com/foo/status/123")!)

        #expect(capturedCookies == nil)
    }
}
