import Foundation

struct ExtractedArticle: Decodable, Sendable {
    let text: String
    let title: String?
    let url: String
    let language: String?
}

struct PronunciationCandidate: Codable, Sendable, Identifiable, Hashable {
    let kind: String
    let label: String
    let ssml: String

    var id: String { ssml }
}

enum HealthStatus: Equatable, Sendable { case ready, loading }

enum BackendError: Error, Sendable {
    case backendNotReady
    case azureNotConfigured
    case extractFailed(String)
    case generationCancelled
}

extension BackendError: Equatable {}
