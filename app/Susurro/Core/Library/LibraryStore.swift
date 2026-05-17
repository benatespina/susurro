import Foundation
import Observation
import os

@MainActor
@Observable
final class LibraryStore {
    private(set) var items: [LibraryItem] = []

    private let libraryRoot: URL
    private let libraryDir: URL
    private let audioDir: URL
    private let itemsFileURL: URL

    init(applicationSupportRoot: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Susurro")) {
        self.libraryRoot = applicationSupportRoot
        self.libraryDir = applicationSupportRoot.appending(path: "library")
        self.audioDir = applicationSupportRoot.appending(path: "library/audio")
        self.itemsFileURL = applicationSupportRoot.appending(path: "library/items.json")
    }

    func load() {
        do {
            try FileManager.default.createDirectory(
                at: libraryDir,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: audioDir,
                withIntermediateDirectories: true
            )
        } catch {
            AppLogger.app.error("LibraryStore: failed to create directories: \(error, privacy: .public)")
        }

        guard let data = try? Data(contentsOf: itemsFileURL) else {
            items = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([LibraryItem].self, from: data)
            items = decoded.sorted { $0.createdAt > $1.createdAt }
            AppLogger.app.info("LibraryStore: loaded \(self.items.count, privacy: .public) items")
        } catch {
            AppLogger.app.error("LibraryStore: failed to decode items.json: \(error, privacy: .public)")
            items = []
        }
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: itemsFileURL, options: [.atomic])
    }

    func add(_ item: LibraryItem) {
        items.append(item)
        items.sort { $0.createdAt > $1.createdAt }
        do {
            try save()
        } catch {
            AppLogger.app.error("LibraryStore: failed to save after add: \(error, privacy: .public)")
        }
    }

    func update(id: UUID, _ mutate: (inout LibraryItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        do {
            try save()
        } catch {
            AppLogger.app.error("LibraryStore: failed to save after update: \(error, privacy: .public)")
        }
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        items.remove(at: index)
        do {
            try save()
        } catch {
            AppLogger.app.error("LibraryStore: failed to save after remove: \(error, privacy: .public)")
        }
        if let audioFilename = item.audioFilename {
            let audioURL = audioDir.appending(path: audioFilename)
            do {
                try FileManager.default.removeItem(at: audioURL)
            } catch {
                AppLogger.app.error("LibraryStore: failed to delete audio file \(audioFilename, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    func audioURL(for item: LibraryItem) -> URL? {
        guard let audioFilename = item.audioFilename else { return nil }
        return audioDir.appending(path: audioFilename)
    }
}
