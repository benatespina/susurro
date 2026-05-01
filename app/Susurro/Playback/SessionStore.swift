import Foundation

struct PersistedSession: Codable, Sendable, Equatable {
    var text: String
    var chunks: [String]
    var currentChunkIndex: Int
    var savedAt: Date
}

enum SessionStore {
    static var fileURL: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Application Support/Susurro/last_session.json")
    }

    static func load() -> PersistedSession? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedSession.self, from: data)
    }

    static func save(_ session: PersistedSession) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
