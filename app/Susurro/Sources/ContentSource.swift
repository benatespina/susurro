import Foundation

enum ResolvedSource: Sendable {
    case browserURL(String)
    case pdfFile(URL)
    case fullText(text: String, title: String?)
}

struct ResolvedContent: Sendable {
    let text: String
    let title: String?
    let language: String?
}

enum ContentExtractionError: Error {
    case noSource
    case backendNotReady
    case fetchFailed(String)
    case emptyText
}
