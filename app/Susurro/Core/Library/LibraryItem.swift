import Foundation

enum SourceKind: String, Codable, Sendable {
    case url
    case text
}

enum LibraryItemStatus: Sendable, Equatable {
    case pending
    case extracting
    case synthesizing(progress: Double?)
    case uploading
    case ready
    case played
    case archived
    case failed(reason: String)
}

extension LibraryItemStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case progress
        case reason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "pending":
            self = .pending
        case "extracting":
            self = .extracting
        case "synthesizing":
            let progress = try container.decodeIfPresent(Double.self, forKey: .progress)
            self = .synthesizing(progress: progress)
        case "uploading":
            self = .uploading
        case "ready":
            self = .ready
        case "played":
            self = .played
        case "archived":
            self = .archived
        case "failed":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .failed(reason: reason)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown LibraryItemStatus type: \(type_)"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:
            try container.encode("pending", forKey: .type)
        case .extracting:
            try container.encode("extracting", forKey: .type)
        case .synthesizing(let progress):
            try container.encode("synthesizing", forKey: .type)
            try container.encodeIfPresent(progress, forKey: .progress)
        case .uploading:
            try container.encode("uploading", forKey: .type)
        case .ready:
            try container.encode("ready", forKey: .type)
        case .played:
            try container.encode("played", forKey: .type)
        case .archived:
            try container.encode("archived", forKey: .type)
        case .failed(let reason):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

struct LibraryItem: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var title: String?
    var sourceURL: String?
    var sourceKind: SourceKind
    var rawText: String?
    var status: LibraryItemStatus
    var audioFilename: String?
    var durationSeconds: Double?
    var byteSize: Int64?
    var lastError: String?
    var playedAt: Date?
    var driveFileID: String?

    /// Ready-state item whose audio is synthesised but not yet on Drive.
    var isOrphan: Bool {
        guard case .ready = status else { return false }
        return driveFileID == nil && audioFilename != nil
    }
}
