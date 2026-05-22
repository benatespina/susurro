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

    static func extract(html: String, url: String) -> (text: String, title: String?, containerTag: String?, linkTextLength: Int, totalTextLength: Int)? {
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
        var matchedContainerTag: String?
        for selector in containerSelectors {
            if let el = try? doc.select(selector).first(),
               let t = try? el.text(), !t.isEmpty {
                container = el
                // Treat <div role="main"> semantically identical to <main> so the
                // quality-gate +2 container bonus fires for role-main pages.
                matchedContainerTag = selector == "[role=main]" ? "main" : el.tagName().lowercased()
                break
            }
        }
        guard let container else { return nil }

        // Compute link text length before stripping any content.
        let anchors = (try? container.select("a")) ?? Elements()
        let linkTextLength = anchors.reduce(0) { sum, anchor in
            sum + ((try? anchor.text()) ?? "").count
        }

        let nodes = (try? container.select(textSelectors)) ?? Elements()
        var parts: [String] = []
        for node in nodes {
            // Skip elements that contain other text-bearing descendants — those
            // descendants will be emitted individually, so including the wrapper
            // here would duplicate their text. Common case: <blockquote> with
            // nested <p>, or <li> with nested block elements.
            if hasMatchingDescendant(node) {
                continue
            }
            let piece = (try? node.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !piece.isEmpty {
                parts.append(piece)
            }
        }

        let text = parts.joined(separator: "\n\n")
        guard !text.isEmpty else { return nil }

        return (text, title, matchedContainerTag, linkTextLength, text.count)
    }

    private static let textSelectorTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote",
    ]

    private static func hasMatchingDescendant(_ element: Element) -> Bool {
        for child in element.children() {
            if textSelectorTags.contains(child.tagName().lowercased()) {
                return true
            }
            if hasMatchingDescendant(child) {
                return true
            }
        }
        return false
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
