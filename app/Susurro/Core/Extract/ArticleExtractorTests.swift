import Foundation
import Testing
@testable import Susurro

// MARK: - URLProtocol Mock

nonisolated(unsafe) private var mockResponseHTML: String = ""
nonisolated(unsafe) private var mockShouldError: Bool = false

private final class ArticleMockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if mockShouldError {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let data = mockResponseHTML.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeMockSession(html: String, shouldError: Bool = false) -> URLSession {
    mockResponseHTML = html
    mockShouldError = shouldError
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ArticleMockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Long HTML fixture

private let longArticleHTML = """
<!DOCTYPE html><html><head><title>Long Article</title></head><body><article>
<p>This is a very detailed article about a fascinating topic that spans many paragraphs. \
The author has done extensive research to bring readers the most comprehensive overview \
of the subject matter, examining every angle with care and precision.</p>
<p>In the second paragraph, we dive deeper into the nuances of the topic, exploring \
the historical context and how various factors have contributed to the current state \
of affairs. Experts have been consulted extensively to ensure accuracy.</p>
<p>The conclusion ties everything together, offering a forward-looking perspective on \
what might happen next and how readers can stay informed on this ever-evolving topic.</p>
</article></body></html>
"""

// MARK: - Tests

// MARK: - Fake strategy helper

private final class FakeStrategy: ArticleExtractionStrategy, @unchecked Sendable {
    private let hostMatch: String
    private let result: Result<(text: String, title: String?), any Error>
    private(set) var extractCallCount = 0

    init(
        matchingHost: String,
        result: Result<(text: String, title: String?), any Error>
    ) {
        self.hostMatch = matchingHost
        self.result = result
    }

    func canHandle(_ url: URL) -> Bool {
        url.host == hostMatch
    }

    func extract(url: URL) async throws -> (text: String, title: String?) {
        extractCallCount += 1
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

// MARK: - Tests

@Suite("ArticleExtractor", .serialized)
struct ArticleExtractorTests {

    @Test("happy path: SwiftSoup result > 100 chars, reader not invoked")
    func happyPathSwiftSoup() async throws {
        let session = makeMockSession(html: longArticleHTML)
        // Use enough long words (>3 chars) so the quality gate accepts the result.
        // 90 × 1 long word "fascinating" → word count ≥ 80 → +1; article container → +2; score = 3 ≥ 2.
        let longText = Array(repeating: "fascinating", count: 90).joined(separator: " ")
        let readerInvokedBox = ActorBox(false)

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in (longText, "Long Article", "article", 0, longText.count) },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return ("reader text", nil)
            },
            strategies: []
        )

        let article = try await extractor.extract(url: "https://example.com/article")
        #expect(article.text == longText)
        #expect(article.title == "Long Article")
        #expect(article.url == "https://example.com/article")
        let invoked = await readerInvokedBox.value
        #expect(!invoked)
    }

    @Test("fallback: SwiftSoup returns short text, reader is invoked")
    func fallbackToReader() async throws {
        let session = makeMockSession(html: "<html><body><p>short</p></body></html>")
        let readerText = String(repeating: "Reader content for testing the fallback path. ", count: 5)
        let readerInvokedBox = ActorBox(false)

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in ("short", nil, "body", 0, 5) },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return (readerText, "Reader Title")
            },
            strategies: []
        )

        let article = try await extractor.extract(url: "https://example.com/article")
        let invoked = await readerInvokedBox.value
        #expect(invoked)
        #expect(article.text == readerText)
        #expect(article.title == "Reader Title")
    }

    @Test("bad URL scheme throws extractFailed")
    func badURLScheme() async throws {
        let extractor = ArticleExtractor(
            session: makeMockSession(html: ""),
            swiftSoupExtract: { _, _ in nil },
            readerExtract: { _ in ("", nil) },
            strategies: []
        )

        await #expect(throws: BackendError.extractFailed("invalid url")) {
            try await extractor.extract(url: "ftp://x")
        }
    }

    @Test("both extractors empty throws extractFailed")
    func bothExtractorsEmpty() async throws {
        let session = makeMockSession(html: "<html><body></body></html>")

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in nil },
            readerExtract: { _ in ("", nil) },
            strategies: []
        )

        await #expect(throws: BackendError.extractFailed("no readable article content")) {
            try await extractor.extract(url: "https://example.com/article")
        }
    }

    @Test("stamps Spanish language for Spanish text")
    func stampsSpanishLanguage() async throws {
        let spanishText = String(repeating: "El artículo habla sobre los avances científicos en España. ", count: 5)
        let session = makeMockSession(html: "<html><body><p>x</p></body></html>")

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in (spanishText, "Título", "article", 0, spanishText.count) },
            readerExtract: { _ in ("", nil) },
            strategies: []
        )

        let article = try await extractor.extract(url: "https://example.es/articulo")
        #expect(article.language == "es")
    }

    // MARK: - Tier-1 quality gate tests

    @Test("tier1: consent banner (EN) forces tier-2 reader invocation")
    func tier1RejectedForConsentBannerEnglish() async throws {
        // Three distinct EN consent phrases embedded in short text → gate rejects.
        let bannerText = """
        We use cookies to personalise content. Accept cookies to continue. \
        Our cookie policy explains how we use essential cookies and personalised ads \
        to improve your experience on our website.
        """
        let session = makeMockSession(html: "<html><body><p>x</p></body></html>")
        let readerInvokedBox = ActorBox(false)
        let readerText = String(repeating: "Real content from reader. ", count: 10)

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in (bannerText, nil, "body", 0, bannerText.count) },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return (readerText, nil)
            },
            strategies: []
        )

        _ = try await extractor.extract(url: "https://example.com/article")
        let invoked = await readerInvokedBox.value
        #expect(invoked)
    }

    @Test("tier1: link-list page forces tier-2 reader invocation")
    func tier1RejectedForLinkListPage() async throws {
        // 50 long words but link density > 0.5 with body container → gate rejects.
        let linkText = String(repeating: "navigating through links ", count: 10) // ~50 words, all anchor
        let session = makeMockSession(html: "<html><body><p>x</p></body></html>")
        let readerInvokedBox = ActorBox(false)
        let readerText = String(repeating: "Real content from reader. ", count: 10)

        let extractor = ArticleExtractor(
            session: session,
            // linkTextLength == totalTextLength → density = 1.0 > 0.5, body → gate rejects
            swiftSoupExtract: { _, _ in (linkText, nil, "body", linkText.count, linkText.count) },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return (readerText, nil)
            },
            strategies: []
        )

        _ = try await extractor.extract(url: "https://example.com/links")
        let invoked = await readerInvokedBox.value
        #expect(invoked)
    }

    @Test("tier1: article container with 250 long words and no consent phrases is accepted without tier-2")
    func tier1AcceptedForRealArticleWithArticleContainer() async throws {
        // 65 × 4 words = 260 long words → +4 (≥250 tier); article container → +2; total = 6 ≥ 2 → accepted.
        let articleWords = (Array(repeating: "fascinating incredible amazing discovery", count: 65)).joined(separator: " ")
        let session = makeMockSession(html: "<html><body><p>x</p></body></html>")
        let readerInvokedBox = ActorBox(false)

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in (articleWords, "Article", "article", 0, articleWords.count) },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return ("reader content", nil)
            },
            strategies: []
        )

        _ = try await extractor.extract(url: "https://example.com/article")
        let invoked = await readerInvokedBox.value
        #expect(!invoked)
    }

    // MARK: - Strategy fallback tests

    @Test("xcom fallback invoked when tier-2 fails")
    func xcomFallbackInvokedWhenTier2Fails() async throws {
        let session = makeMockSession(html: "<html><body></body></html>")
        let strategyText = "Tweet text from strategy."
        let fakeStrategy = FakeStrategy(
            matchingHost: "x.com",
            result: .success((text: strategyText, title: "Tweet Author"))
        )

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in nil },
            readerExtract: { _ in throw BackendError.extractFailed("reader returned no content") },
            strategies: [fakeStrategy]
        )

        let article = try await extractor.extract(url: "https://x.com/someone/status/123")
        #expect(article.text == strategyText)
        #expect(article.title == "Tweet Author")
        #expect(fakeStrategy.extractCallCount == 1)
    }

    @Test("xcom fallback skipped when canHandle returns false")
    func xcomFallbackSkippedWhenCanHandleFalse() async throws {
        let session = makeMockSession(html: "<html><body></body></html>")
        // Strategy only matches "x.com", but the URL is "example.com" — canHandle returns false.
        let fakeStrategy = FakeStrategy(
            matchingHost: "x.com",
            result: .success((text: "should not be returned", title: nil))
        )

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in nil },
            readerExtract: { _ in ("", nil) },
            strategies: [fakeStrategy]
        )

        await #expect(throws: BackendError.extractFailed("no readable article content")) {
            try await extractor.extract(url: "https://example.com/article")
        }
        #expect(fakeStrategy.extractCallCount == 0)
    }

    @Test("original error rethrown when strategy also fails")
    func originalErrorRethrownWhenStrategyAlsoFails() async throws {
        let session = makeMockSession(html: "<html><body></body></html>")
        let fakeStrategy = FakeStrategy(
            matchingHost: "x.com",
            result: .failure(BackendError.extractFailed("oEmbed HTTP 404"))
        )

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in nil },
            readerExtract: { _ in throw BackendError.extractFailed("reader returned no content") },
            strategies: [fakeStrategy]
        )

        // When the strategy also fails, the ORIGINAL tier-2 error should be re-thrown.
        await #expect(throws: BackendError.extractFailed("reader returned no content")) {
            try await extractor.extract(url: "https://x.com/someone/status/999")
        }
    }
}

// MARK: - Helper

private actor ActorBox<T: Sendable> {
    private(set) var value: T

    init(_ value: T) {
        self.value = value
    }

    func set(_ newValue: T) {
        value = newValue
    }
}
