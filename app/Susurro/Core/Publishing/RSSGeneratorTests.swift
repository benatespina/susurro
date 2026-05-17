import Foundation
import Testing
@testable import Susurro

@Suite("RSSGenerator")
struct RSSGeneratorTests {

    // MARK: - Helpers

    private func makeChannel() -> RSSChannel {
        RSSChannel(
            title: "Test Podcast",
            description: "A test podcast feed",
            link: URL(string: "https://example.com/feed")!,
            language: "en-US",
            imageURL: nil,
            author: "Test Author"
        )
    }

    private func makeItem(
        guid: String = "item-1",
        pubDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        title: String = "Test Item",
        description: String = "Item description",
        enclosureURL: URL = URL(string: "https://drive.google.com/uc?export=download&id=abc")!,
        enclosureLength: Int64 = 12345,
        durationSeconds: Double = 120,
        link: URL? = URL(string: "https://example.com/article")
    ) -> RSSItem {
        RSSItem(
            guid: guid,
            pubDate: pubDate,
            title: title,
            description: description,
            enclosureURL: enclosureURL,
            enclosureLength: enclosureLength,
            durationSeconds: durationSeconds,
            link: link
        )
    }

    // MARK: - Snapshot test

    @Test func renderProducesValidXMLStructure() {
        let channel = makeChannel()
        let items = [makeItem(guid: "guid-1", title: "Article One"), makeItem(guid: "guid-2", title: "Article Two")]
        let output = RSSGenerator.render(channel: channel, items: items)

        #expect(output.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(output.contains("<rss version=\"2.0\""))
        #expect(output.contains("xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\""))
        #expect(output.contains("<channel>"))
        #expect(output.contains("</channel>"))
        #expect(output.contains("</rss>"))
        #expect(output.contains("<title>Test Podcast</title>"))
        #expect(output.contains("<description>A test podcast feed</description>"))
        #expect(output.contains("<language>en-US</language>"))
        #expect(output.contains("<itunes:author>Test Author</itunes:author>"))
        #expect(output.contains("guid-1"))
        #expect(output.contains("guid-2"))
        #expect(output.contains("Article One"))
        #expect(output.contains("Article Two"))
    }

    @Test func renderWithImageURL() {
        let channel = RSSChannel(
            title: "Feed",
            description: "Desc",
            link: URL(string: "https://example.com")!,
            language: "en",
            imageURL: URL(string: "https://example.com/cover.png")!,
            author: nil
        )
        let output = RSSGenerator.render(channel: channel, items: [])
        #expect(output.contains("<image>"))
        #expect(output.contains("cover.png"))
    }

    // MARK: - XML escape edge cases

    @Test func xmlEscapeAmpersand() {
        #expect(RSSGenerator.xmlEscape("cats & dogs") == "cats &amp; dogs")
    }

    @Test func xmlEscapeLessThan() {
        #expect(RSSGenerator.xmlEscape("<tag>") == "&lt;tag&gt;")
    }

    @Test func xmlEscapeDoubleQuote() {
        #expect(RSSGenerator.xmlEscape("say \"hello\"") == "say &quot;hello&quot;")
    }

    @Test func xmlEscapeSingleQuote() {
        #expect(RSSGenerator.xmlEscape("it's") == "it&apos;s")
    }

    @Test func xmlEscapeMultipleEntities() {
        let input = "<a href=\"url\">A & B</a>"
        let expected = "&lt;a href=&quot;url&quot;&gt;A &amp; B&lt;/a&gt;"
        #expect(RSSGenerator.xmlEscape(input) == expected)
    }

    @Test func titleWithSpecialCharsIsEscapedInOutput() {
        let channel = makeChannel()
        let item = makeItem(title: "A&B <article>")
        let output = RSSGenerator.render(channel: channel, items: [item])
        #expect(output.contains("A&amp;B &lt;article&gt;"))
        #expect(!output.contains("A&B"))
    }

    // MARK: - RFC 822 pubDate

    @Test func pubDateMatchesRFC822Format() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let formatted = RSSGenerator.rfc822Date(date)
        // Pattern: "Wed, 15 Nov 2023 ..." — verify format with regex
        let pattern = #"^\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(formatted.startIndex..., in: formatted)
        let matched = regex?.firstMatch(in: formatted, range: range) != nil
        #expect(matched, "pubDate '\(formatted)' does not match RFC 822 pattern")
    }

    // MARK: - Duration formatting

    @Test func formatDurationZeroSeconds() {
        #expect(RSSGenerator.formatDuration(0) == "0:00")
    }

    @Test func formatDurationFortyFiveSeconds() {
        #expect(RSSGenerator.formatDuration(45) == "0:45")
    }

    @Test func formatDurationOneHour() {
        #expect(RSSGenerator.formatDuration(3600) == "1:00:00")
    }

    @Test func formatDurationComplexValue() {
        // 7384 seconds = 2h 3m 4s
        #expect(RSSGenerator.formatDuration(7384) == "2:03:04")
    }

    @Test func formatDurationFiftyNineMinutes() {
        // 3599 seconds = 59m 59s
        #expect(RSSGenerator.formatDuration(3599) == "59:59")
    }

    // MARK: - Empty items list

    @Test func emptyItemsListProducesValidChannelOnly() {
        let channel = makeChannel()
        let output = RSSGenerator.render(channel: channel, items: [])
        #expect(output.contains("<channel>"))
        #expect(output.contains("</channel>"))
        #expect(!output.contains("<item>"))
    }

    // MARK: - Enclosure attributes

    @Test func enclosureContainsRequiredAttributes() {
        let channel = makeChannel()
        let item = makeItem(enclosureLength: 98765)
        let output = RSSGenerator.render(channel: channel, items: [item])
        #expect(output.contains("length=\"98765\""))
        #expect(output.contains("type=\"audio/mpeg\""))
        #expect(output.contains("export=download"))
    }

    // MARK: - Optional link field

    @Test func itemWithoutLinkOmitsLinkTag() {
        let channel = makeChannel()
        let item = makeItem(link: nil)
        let output = RSSGenerator.render(channel: channel, items: [item])
        // Should not contain <link> inside <item> context for a missing link.
        // Channel link IS there so we check item section doesn't have link.
        let itemStart = output.range(of: "<item>")
        let itemEnd = output.range(of: "</item>")
        if let start = itemStart, let end = itemEnd {
            let itemContent = String(output[start.lowerBound..<end.upperBound])
            #expect(!itemContent.contains("<link>"))
        }
    }

    @Test func itemWithLinkIncludesLinkTag() {
        let channel = makeChannel()
        let item = makeItem(link: URL(string: "https://example.com/article/42")!)
        let output = RSSGenerator.render(channel: channel, items: [item])
        #expect(output.contains("https://example.com/article/42"))
    }
}
