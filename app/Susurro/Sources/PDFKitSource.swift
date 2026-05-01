import AppKit
import ApplicationServices
import PDFKit

enum PDFKitSource {
    static func currentDocumentURL(pid: pid_t) -> URL? {
        let appElement = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &winRef
        ) == .success, let winRef else { return nil }
        let window = winRef as! AXUIElement // swiftlint:disable:this force_cast

        var docRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXDocumentAttribute as CFString, &docRef
        ) == .success, let docRef else { return nil }

        if let urlString = docRef as? String, let url = URL(string: urlString) {
            return url
        }
        if let url = docRef as? URL { return url }
        return nil
    }

    static func extractText(from url: URL) throws -> ResolvedContent {
        guard let document = PDFDocument(url: url) else {
            throw ContentExtractionError.fetchFailed("could not open PDF at \(url.path)")
        }
        return try extract(from: document, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    static func extractText(fromRemote url: URL) async throws -> ResolvedContent {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentExtractionError.fetchFailed("HTTP \(http.statusCode) downloading PDF")
        }
        guard let document = PDFDocument(data: data) else {
            throw ContentExtractionError.fetchFailed("could not parse PDF from \(url.absoluteString)")
        }
        return try extract(from: document, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    private static func extract(from document: PDFDocument, fallbackTitle: String) throws -> ResolvedContent {
        var pieces: [String] = []
        pieces.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string, !text.isEmpty {
                pieces.append(text)
            }
        }
        let combined = pieces.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty {
            throw ContentExtractionError.emptyText
        }
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            ?? fallbackTitle
        return ResolvedContent(text: combined, title: title, language: nil)
    }
}
