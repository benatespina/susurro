import Foundation
import Testing
@testable import Susurro

// MARK: - URLProtocol Mock

// Named with module prefix to avoid collision with BackendProcessTests.MockURLProtocol
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

@Suite("ArticleExtractor", .serialized)
struct ArticleExtractorTests {

    @Test("happy path: SwiftSoup result > 100 chars, reader not invoked")
    func happyPathSwiftSoup() async throws {
        let session = makeMockSession(html: longArticleHTML)
        let longText = String(repeating: "This is extracted article content. ", count: 5)
        let readerInvokedBox = ActorBox(false)

        let extractor = ArticleExtractor(
            session: session,
            swiftSoupExtract: { _, _ in (longText, "Long Article") },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return ("reader text", nil)
            }
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
            swiftSoupExtract: { _, _ in ("short", nil) },
            readerExtract: { _ in
                await readerInvokedBox.set(true)
                return (readerText, "Reader Title")
            }
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
            readerExtract: { _ in ("", nil) }
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
            readerExtract: { _ in ("", nil) }
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
            swiftSoupExtract: { _, _ in (spanishText, "Título") },
            readerExtract: { _ in ("", nil) }
        )

        let article = try await extractor.extract(url: "https://example.es/articulo")
        #expect(article.language == "es")
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
