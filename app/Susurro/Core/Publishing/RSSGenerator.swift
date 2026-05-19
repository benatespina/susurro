import Foundation

// MARK: - Channel & Item models

struct RSSChannel: Sendable {
    let title: String
    let description: String
    let link: URL
    let language: String
    let imageURL: URL?
    let author: String?
}

struct RSSItem: Sendable {
    let guid: String
    let pubDate: Date
    let title: String
    let description: String
    let enclosureURL: URL
    let enclosureLength: Int64
    let durationSeconds: Double
    let link: URL?
}

// MARK: - RSSGenerator

enum RSSGenerator {

    static func render(channel: RSSChannel, items: [RSSItem]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>\(xmlEscape(channel.title))</title>
            <description>\(xmlEscape(channel.description))</description>
            <link>\(xmlEscape(channel.link.absoluteString))</link>
            <language>\(xmlEscape(channel.language))</language>
        """

        if let imageURL = channel.imageURL {
            xml += """

                <image>
                  <url>\(xmlEscape(imageURL.absoluteString))</url>
                  <title>\(xmlEscape(channel.title))</title>
                  <link>\(xmlEscape(channel.link.absoluteString))</link>
                </image>
                <itunes:image href="\(xmlEscape(imageURL.absoluteString))"/>
            """
        }

        if let author = channel.author {
            xml += "\n    <itunes:author>\(xmlEscape(author))</itunes:author>"
        }

        for item in items {
            xml += "\n"
            xml += renderItem(item)
        }

        xml += """

          </channel>
        </rss>
        """
        return xml
    }

    // MARK: - Private: item rendering

    private static func renderItem(_ item: RSSItem) -> String {
        var block = """
            <item>
              <title>\(xmlEscape(item.title))</title>
              <description>\(xmlEscape(item.description))</description>
              <guid isPermaLink="false">\(xmlEscape(item.guid))</guid>
              <pubDate>\(rfc822Date(item.pubDate))</pubDate>
              <enclosure url="\(xmlEscape(item.enclosureURL.absoluteString))" length="\(item.enclosureLength)" type="audio/mpeg"/>
              <itunes:duration>\(formatDuration(item.durationSeconds))</itunes:duration>
        """
        if let link = item.link {
            block += "\n      <link>\(xmlEscape(link.absoluteString))</link>"
        }
        block += "\n    </item>"
        return block
    }

    // MARK: - Private: XML escape

    static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Private: RFC 822 date formatting

    static func rfc822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: - Private: duration HH:MM:SS

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
