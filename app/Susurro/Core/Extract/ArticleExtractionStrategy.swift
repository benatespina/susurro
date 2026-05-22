import Foundation

protocol ArticleExtractionStrategy: Sendable {
    func canHandle(_ url: URL) -> Bool
    func extract(url: URL) async throws -> (text: String, title: String?)
}
