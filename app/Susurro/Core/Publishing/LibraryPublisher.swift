import Foundation

// MARK: - Protocol

protocol LibraryPublishing: Sendable {
    func publish(itemID: UUID) async throws
    func unpublish(itemID: UUID) async throws
    func regenerateFeed() async throws
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
        guard let item = await loadItem(itemID) else {
            throw PublisherError.itemNotFound
        }
        await setStatus(id: itemID, status: .uploading)

        do {
            guard let config = configProvider(), let folderID = config.folderID else {
                throw PublisherError.notConnected
            }

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

            // Regenerate and upload feed.
            try await uploadFeed(config: config)

            await setStatus(id: itemID, status: .ready)

        } catch {
            await setStatus(id: itemID, status: .failed(reason: String(describing: error)))
            throw error
        }
    }

    func unpublish(itemID: UUID) async throws {
        guard let item = await loadItem(itemID) else {
            throw PublisherError.itemNotFound
        }

        if let fileID = item.driveFileID {
            try await driveClient.deleteFile(fileID: fileID)
        }

        await MainActor.run {
            store.update(id: itemID) { i in
                i.driveFileID = nil
            }
        }

        try await regenerateFeed()
    }

    func regenerateFeed() async throws {
        guard let config = configProvider() else { return }
        try await uploadFeed(config: config)
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
            let updated = DriveConfig(
                clientID: config.clientID,
                clientSecret: config.clientSecret,
                refreshToken: config.refreshToken,
                accessToken: config.accessToken,
                accessTokenExpiry: config.accessTokenExpiry,
                folderID: config.folderID,
                feedFileID: newFeedFileID
            )
            DriveConfig.save(updated)
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
