import Testing
@testable import Susurro

@Suite("SwiftSoupExtractor")
struct SwiftSoupExtractorTests {

    // MARK: - Fixtures

    private let blogPostHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>My Blog Post</title></head>
    <body>
    <article>
        <h1>The Great Adventure</h1>
        <p>Once upon a time in a land far away, there was a traveller who set out on a long journey through mountains and valleys, discovering the world one step at a time.</p>
        <p>Along the way he met many curious people and creatures, each teaching him something new about life, courage, and the importance of perseverance in the face of adversity.</p>
        <p>By the end of his travels he had amassed a fortune in wisdom, and returned home a changed man — ready to share his stories with all who would listen.</p>
    </article>
    </body>
    </html>
    """

    private let newsSiteHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>News Article Title</title>
        <meta property="og:title" content="OG Title Should Be Ignored" />
    </head>
    <body>
    <nav><a href="/">Home</a></nav>
    <main>
        <h1>Breaking News: Something Happened</h1>
        <p>Details of the news event are emerging as reporters on the ground continue to file updates from the scene throughout the day.</p>
        <p>Experts from multiple fields have weighed in, offering a range of perspectives on the potential consequences of the situation as it unfolds.</p>
        <aside><p>Related: Other news stories you might enjoy reading today.</p></aside>
        <p>The government has responded with a statement acknowledging the situation and promising a full investigation into the circumstances.</p>
    </main>
    <footer><p>Copyright 2026</p></footer>
    </body>
    </html>
    """

    private let minimalBodyHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Minimal Page</title></head>
    <body>
        <p>This is the first paragraph of a very simple page with only body-level paragraphs and nothing else around it.</p>
        <p>A second paragraph follows here, adding more content to ensure the extractor finds something useful to work with.</p>
        <p>And a third paragraph rounds out this minimal but valid document structure for testing purposes.</p>
    </body>
    </html>
    """

    private let navFooterOnlyHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>No Content Page</title></head>
    <body>
    <nav>
        <ul><li><a href="/about">About</a></li><li><a href="/contact">Contact</a></li></ul>
    </nav>
    <footer>
        <p>Privacy Policy | Terms of Service</p>
    </footer>
    </body>
    </html>
    """

    // MARK: - Tests

    @Test("extracts text from article-wrapped blog post")
    func blogPostWithArticle() throws {
        let result = SwiftSoupExtractor.extract(html: blogPostHTML, url: "https://example.com/post")
        let unwrapped = try #require(result)
        #expect(unwrapped.text.contains("Great Adventure"))
        #expect(unwrapped.text.contains("traveller"))
        #expect(unwrapped.title == "My Blog Post")
        #expect(unwrapped.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 100)
    }

    @Test("strips aside from news main container")
    func newsSiteStripsAside() throws {
        let result = SwiftSoupExtractor.extract(html: newsSiteHTML, url: "https://news.example.com/article")
        let unwrapped = try #require(result)
        #expect(unwrapped.text.contains("Breaking News"))
        #expect(unwrapped.text.contains("government has responded"))
        #expect(!unwrapped.text.contains("Related: Other news stories"))
    }

    @Test("title element wins over og:title")
    func titlePrecedence() throws {
        let result = SwiftSoupExtractor.extract(html: newsSiteHTML, url: "https://news.example.com/article")
        let unwrapped = try #require(result)
        #expect(unwrapped.title == "News Article Title")
        #expect(unwrapped.title != "OG Title Should Be Ignored")
    }

    @Test("extracts text from minimal body-only page")
    func minimalBodyPage() throws {
        let result = SwiftSoupExtractor.extract(html: minimalBodyHTML, url: "https://example.com/minimal")
        let unwrapped = try #require(result)
        #expect(unwrapped.text.contains("first paragraph"))
        #expect(unwrapped.text.contains("second paragraph"))
        #expect(unwrapped.title == "Minimal Page")
    }

    @Test("returns nil when page has only nav and footer")
    func navFooterOnlyReturnsNil() {
        let result = SwiftSoupExtractor.extract(html: navFooterOnlyHTML, url: "https://example.com/empty")
        #expect(result == nil)
    }

    @Test("blockquote with nested paragraphs does not duplicate text")
    func nestedBlockquoteDoesNotDuplicate() throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Quote Test</title></head>
        <body>
        <article>
            <p>An introduction sentence appears before the quoted section so the article has some context.</p>
            <blockquote>
                <p>First quoted paragraph that should appear exactly once in the extracted text output.</p>
                <p>Second quoted paragraph that should also appear exactly once in the extracted text output.</p>
            </blockquote>
            <p>A closing paragraph wraps up the article after the quoted section ends.</p>
        </article>
        </body>
        </html>
        """
        let result = SwiftSoupExtractor.extract(html: html, url: "https://example.com/quote")
        let unwrapped = try #require(result)
        let occurrences = unwrapped.text.components(separatedBy: "First quoted paragraph").count - 1
        #expect(occurrences == 1)
        let occurrencesSecond = unwrapped.text.components(separatedBy: "Second quoted paragraph").count - 1
        #expect(occurrencesSecond == 1)
    }
}
