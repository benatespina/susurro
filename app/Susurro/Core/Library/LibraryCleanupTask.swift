import Foundation
import os

// MARK: - ClockProviding

protocol ClockProviding: Sendable {
    var now: Date { get }
}

struct SystemClock: ClockProviding {
    var now: Date { Date() }
}

// MARK: - LibraryCleanupTask

actor LibraryCleanupTask {
    private let store: LibraryStore
    private let publisher: (any LibraryPublishing)?
    private let settings: LibrarySettings
    private let audioDirectoryURL: URL
    private let clock: any ClockProviding
    private let fileManager: FileManager

    init(
        store: LibraryStore,
        publisher: (any LibraryPublishing)?,
        settings: LibrarySettings,
        audioDirectoryURL: URL,
        clock: any ClockProviding = SystemClock(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.publisher = publisher
        self.settings = settings
        self.audioDirectoryURL = audioDirectoryURL
        self.clock = clock
        self.fileManager = fileManager
    }

    func runOnce() async {
        let items = await MainActor.run { store.items }
        let ttlDays = await MainActor.run { settings.playedTTLDays }
        let ttl = TimeInterval(ttlDays * 86400)
        let now = clock.now

        var changed = false

        for item in items {
            guard item.status == .played,
                  let playedAt = item.playedAt,
                  now.timeIntervalSince(playedAt) > ttl
            else { continue }

            // Archive the item and clear audioFilename.
            let audioFilename = item.audioFilename
            await MainActor.run {
                store.update(id: item.id) { i in
                    i.status = .archived
                    i.audioFilename = nil
                }
            }

            // Delete local audio file (best effort).
            if let filename = audioFilename {
                let audioURL = audioDirectoryURL.appendingPathComponent(filename)
                do {
                    try fileManager.removeItem(at: audioURL)
                } catch {
                    AppLogger.app.warning(
                        "LibraryCleanupTask: failed to delete audio \(filename, privacy: .public): \(error, privacy: .public)"
                    )
                }
            }

            // Remove from Drive (best effort; 404-tolerant in publisher).
            if let pub = publisher {
                try? await pub.unpublish(itemID: item.id)
            }

            changed = true
        }

        // Regenerate feed once if anything changed.
        if changed, let pub = publisher {
            try? await pub.regenerateFeed()
        }
    }
}
