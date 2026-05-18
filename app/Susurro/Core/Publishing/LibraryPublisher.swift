import Foundation

// MARK: - Protocol

protocol LibraryPublishing: Sendable {
    func publish(itemID: UUID) async throws
    func unpublish(itemID: UUID) async throws
    func regenerateFeed() async throws
    func publishOrphans() async
}

// MARK: - Errors

enum PublisherError: Error, Sendable {
    case itemNotFound
    case notConnected
    case audioFileNotFound(String)
}

// MARK: - LibraryPublisher

actor LibraryPublisher: LibraryPublishing {

    // MARK: - Dependencies

    private let store: LibraryStore
    private let driveClient: any DriveUploading
    private let configProvider: @Sendable () -> DriveConfig?
    private let channel: RSSChannel
    private let audioDirectoryOverride: URL?

    // MARK: - Init

    init(
        store: LibraryStore,
        driveClient: any DriveUploading,
        configProvider: @escaping @Sendable () -> DriveConfig?,
        channel: RSSChannel,
        audioDirectory: URL? = nil
    ) {
        self.store = store
        self.driveClient = driveClient
        self.configProvider = configProvider
        self.channel = channel
        self.audioDirectoryOverride = audioDirectory
    }

    // MARK: - LibraryPublishing

    func publish(itemID: UUID) async throws {
        AppLogger.publishing.info("publish start \(itemID.uuidString, privacy: .public)")
        guard let item = await loadItem(itemID) else {
            throw PublisherError.itemNotFound
        }
        await setStatus(id: itemID, status: .uploading)

        // Stage A — MP3 upload (with idempotency check).
        do {
            guard let config = configProvider(), let folderID = config.folderID else {
                throw PublisherError.notConnected
            }

            var mp3AlreadyOnDrive = false
            if let existingFileID = item.driveFileID {
                do {
                    mp3AlreadyOnDrive = try await driveClient.headFile(fileID: existingFileID) != nil
                } catch {
                    AppLogger.publishing.debug("publish: headFile check failed for \(existingFileID, privacy: .public), will re-upload: \(error, privacy: .public)")
                }
                if mp3AlreadyOnDrive {
                    AppLogger.publishing.info("publish: MP3 reused \(existingFileID, privacy: .public)")
                }
            }
            if !mp3AlreadyOnDrive {
                // Read MP3 from disk.
                let audioFilename = "\(item.id.uuidString).mp3"
                let audioURL = audioDirectory().appendingPathComponent(audioFilename)
                guard FileManager.default.fileExists(atPath: audioURL.path) else {
                    throw PublisherError.audioFileNotFound(audioURL.path)
                }
                let mp3Data = try Data(contentsOf: audioURL)

                // Upload MP3.
                let fileID = try await driveClient.uploadFile(
                    name: audioFilename,
                    mimeType: "audio/mpeg",
                    data: mp3Data,
                    parentID: folderID
                )
                try await driveClient.setAnyoneWithLink(fileID: fileID)

                // Persist driveFileID on item.
                await MainActor.run {
                    store.update(id: itemID) { i in
                        i.driveFileID = fileID
                    }
                }
                AppLogger.publishing.info("publish: MP3 uploaded \(fileID, privacy: .public) size=\(mp3Data.count, privacy: .public)")
            }

            // Stage B — Mark .ready immediately once MP3 is on Drive.
            await setStatus(id: itemID, status: .ready)

            // Stage C — Feed regeneration; failure only logs, does not affect item status.
            do {
                try await uploadFeed(config: config)
            } catch {
                AppLogger.publishing.error("feed update failed: \(error, privacy: .public)")
            }

        } catch {
            await setStatus(id: itemID, status: .failed(reason: String(describing: error)))
            throw error
        }
    }

    func unpublish(itemID: UUID) async throws {
        AppLogger.publishing.info("unpublish start \(itemID.uuidString, privacy: .public)")
        guard let item = await loadItem(itemID) else {
            throw PublisherError.itemNotFound
        }

        if let fileID = item.driveFileID {
            try await driveClient.deleteFile(fileID: fileID)
            AppLogger.publishing.info("unpublish: deleted Drive file \(fileID, privacy: .public)")
        }

        await MainActor.run {
            store.update(id: itemID) { i in
                i.driveFileID = nil
            }
        }

        try await regenerateFeed()
        AppLogger.publishing.info("unpublish: feed regenerated for \(itemID.uuidString, privacy: .public)")
    }

    func regenerateFeed() async throws {
        guard let config = configProvider() else { return }
        try await uploadFeed(config: config)
    }

    func publishOrphans() async {
        guard configProvider()?.hasFolder == true else {
            AppLogger.publishing.info("publishOrphans skipped: Drive not configured")
            return
        }
        let orphans = await MainActor.run {
            store.items.filter(\.isOrphan)
        }
        guard !orphans.isEmpty else { return }
        AppLogger.publishing.info("publishOrphans: \(orphans.count, privacy: .public) item(s) to back-publish")
        for item in orphans {
            do {
                try await publish(itemID: item.id)
            } catch {
                AppLogger.publishing.error("publishOrphans: \(item.id.uuidString, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Private: feed upload

    private func uploadFeed(config: DriveConfig) async throws {
        guard let folderID = config.folderID else { throw PublisherError.notConnected }

        let items = await buildRSSItems()
        let feedXML = RSSGenerator.render(channel: channel, items: items)
        let feedData = Data(feedXML.utf8)

        if let feedFileID = config.feedFileID {
            try await driveClient.updateFile(
                fileID: feedFileID,
                data: feedData,
                mimeType: "application/rss+xml"
            )
        } else {
            let newFeedFileID = try await driveClient.uploadFile(
                name: "feed.xml",
                mimeType: "application/rss+xml",
                data: feedData,
                parentID: folderID
            )
            try await driveClient.setAnyoneWithLink(fileID: newFeedFileID)

            // Persist new feedFileID.
            DriveConfig.save(config.copying(feedFileID: newFeedFileID))
        }
    }

    // MARK: - Private: RSS item builder

    private func buildRSSItems() async -> [RSSItem] {
        let storeItems = await MainActor.run { store.items }
        return storeItems.compactMap { item -> RSSItem? in
            // Only include items that have been uploaded to Drive.
            guard let fileID = item.driveFileID else { return nil }
            let enclosureURL = DriveConfig.enclosureURL(forFileID: fileID)
            return RSSItem(
                guid: item.id.uuidString,
                pubDate: item.playedAt ?? item.createdAt,
                title: item.title ?? "Untitled",
                description: item.title ?? "Untitled",
                enclosureURL: enclosureURL,
                enclosureLength: item.byteSize ?? 0,
                durationSeconds: item.durationSeconds ?? 0,
                link: item.sourceURL.flatMap { URL(string: $0) }
            )
        }
    }

    // MARK: - Private: helpers

    private func loadItem(_ id: UUID) async -> LibraryItem? {
        await MainActor.run { store.items.first { $0.id == id } }
    }

    private func setStatus(id: UUID, status: LibraryItemStatus) async {
        await MainActor.run {
            store.update(id: id) { item in
                item.status = status
            }
        }
    }

    private func audioDirectory() -> URL {
        audioDirectoryOverride ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Susurro/library/audio")
    }
}
