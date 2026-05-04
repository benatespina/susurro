import SwiftSoup

enum SwiftSoupExtractor {
    private static let stripSelectors = [
        "nav", "footer", "aside", "script", "style", "noscript", "iframe", "form",
        ".ad", ".ads", ".advertisement", ".social", ".share",
        "header.site-header", "[aria-hidden=true]", "[hidden]",
    ]

    private static let containerSelectors = [
        "article", "main", "[role=main]", ".content", "#content", ".post", ".entry", "body",
    ]

    private static let textSelectors = "p, h1, h2, h3, h4, h5, h6, li, blockquote"

    static func extract(html: String, url: String) -> (text: String, title: String?)? {
        guard let doc = try? SwiftSoup.parse(html, url) else { return nil }

        for selector in stripSelectors {
            try? doc.select(selector).remove()
        }

        removeComments(from: doc)

        let rawTitle = (try? doc.title()) ?? ""
        let title: String?
        if !rawTitle.isEmpty {
            title = rawTitle
        } else if let ogTitle = try? doc.select("meta[property=og:title]").first()?.attr("content"),
                  !ogTitle.isEmpty {
            title = ogTitle
        } else {
            title = nil
        }

        var container: Element?
        for selector in containerSelectors {
            if let el = try? doc.select(selector).first(),
               let t = try? el.text(), !t.isEmpty {
                container = el
                break
            }
        }
        guard let container else { return nil }

        let nodes = (try? container.select(textSelectors)) ?? Elements()
        var parts: [String] = []
        for node in nodes {
            let piece = (try? node.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !piece.isEmpty {
                parts.append(piece)
            }
        }

        let text = parts.joined(separator: "\n\n")
        guard !text.isEmpty else { return nil }

        return (text, title)
    }

    private static func removeComments(from node: Node) {
        var i = 0
        while i < node.childNodeSize() {
            let child = node.childNode(i)
            if child is Comment {
                try? child.remove()
            } else {
                removeComments(from: child)
                i += 1
            }
        }
    }
}
