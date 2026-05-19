import Foundation

// MARK: - Protocol

protocol LibraryPublishing: Sendable {
    func publish(itemID: UUID) async throws
    func unpublish(itemID: UUID) async throws
    func regenerateFeed() async throws
    func publishOrphans() async -> Int
    func reconcileMissing() async -> Int
    func sync() async -> LibraryPublisher.SyncSummary
    func orphanCount() async -> Int
}

// MARK: - Errors

enum PublisherError: Error, Sendable {
    case itemNotFound
    case notConnected
    case audioFileNotFound(String)
}

// MARK: - SyncSummary

extension LibraryPublisher {
    struct SyncSummary: Sendable {
        let orphansPublished: Int
        let missingRePublished: Int
        let feedRegenerated: Bool
    }
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
        try await publishWithoutFeed(itemID: itemID)
        guard let config = configProvider() else { return }
        do {
            try await uploadFeed(config: config)
        } catch {
            AppLogger.publishing.error("feed update failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Private: publishWithoutFeed

    private static func canonicalDriveName(for item: LibraryItem) -> String {
        "\(item.id.uuidString).mp3"
    }

    private func publishWithoutFeed(itemID: UUID) async throws {
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
            } else {
                // driveFileID nil — self-heal by canonical name before uploading.
                let canonicalName = Self.canonicalDriveName(for: item)
                if let foundID = try? await driveClient.findFile(name: canonicalName, parentID: folderID) {
                    AppLogger.publishing.info("publish: self-healed driveFileID from Drive lookup: \(foundID, privacy: .public)")
                    try? await driveClient.setAnyoneWithLink(fileID: foundID)
                    await MainActor.run {
                        store.update(id: itemID) { i in i.driveFileID = foundID }
                    }
                    mp3AlreadyOnDrive = true
                }
            }
            if !mp3AlreadyOnDrive {
                // Read MP3 from disk.
                let audioFilename = Self.canonicalDriveName(for: item)
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

    func publishOrphans() async -> Int {
        guard configProvider()?.hasFolder == true else {
            AppLogger.publishing.info("publishOrphans skipped: Drive not configured")
            return 0
        }
        let orphans = await MainActor.run { store.items.filter(\.isOrphan) }
        guard !orphans.isEmpty else { return 0 }
        AppLogger.publishing.info("publishOrphans: \(orphans.count, privacy: .public) item(s) to back-publish")
        var published = 0
        for item in orphans {
            do {
                try await publishWithoutFeed(itemID: item.id)
                published += 1
            } catch {
                AppLogger.publishing.error("publishOrphans: \(item.id.uuidString, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
        return published
    }

    func reconcileMissing() async -> Int {
        guard configProvider()?.hasFolder == true else { return 0 }
        let candidates = await MainActor.run {
            store.items.filter { item in
                if case .ready = item.status {
                    return item.driveFileID != nil && item.audioFilename != nil
                }
                return false
            }
        }
        guard !candidates.isEmpty else { return 0 }
        var rePublished = 0
        for item in candidates {
            guard let fileID = item.driveFileID else { continue }
            let exists: Bool
            do {
                exists = try await driveClient.headFile(fileID: fileID) != nil
            } catch {
                AppLogger.publishing.debug("reconcileMissing: headFile threw for \(fileID, privacy: .public), treating as missing: \(error, privacy: .public)")
                exists = false
            }
            if exists { continue }
            AppLogger.publishing.info("reconcileMissing: \(item.id.uuidString, privacy: .public) Drive file \(fileID, privacy: .public) gone, re-publishing")
            await MainActor.run { store.update(id: item.id) { $0.driveFileID = nil } }
            do {
                try await publishWithoutFeed(itemID: item.id)
                rePublished += 1
            } catch {
                AppLogger.publishing.error("reconcileMissing: re-publish failed for \(item.id.uuidString, privacy: .public): \(error, privacy: .public)")
            }
        }
        if rePublished > 0 {
            AppLogger.publishing.info("reconcileMissing: re-published \(rePublished, privacy: .public) item(s)")
        }
        return rePublished
    }

    func sync() async -> SyncSummary {
        guard let config = configProvider(), config.hasFolder else {
            AppLogger.publishing.info("sync skipped: Drive not configured")
            return SyncSummary(orphansPublished: 0, missingRePublished: 0, feedRegenerated: false)
        }
        AppLogger.publishing.info("sync start")
        let orphansPublished = await publishOrphans()
        let missingRePublished = await reconcileMissing()
        var feedRegenerated = false
        if orphansPublished > 0 || missingRePublished > 0 {
            do {
                try await uploadFeed(config: config)
                feedRegenerated = true
            } catch {
                AppLogger.publishing.error("sync: feed regen failed: \(error, privacy: .public)")
            }
        }
        AppLogger.publishing.info("sync done — orphans=\(orphansPublished, privacy: .public) missing=\(missingRePublished, privacy: .public) feed=\(feedRegenerated, privacy: .public)")
        return SyncSummary(orphansPublished: orphansPublished, missingRePublished: missingRePublished, feedRegenerated: feedRegenerated)
    }

    func orphanCount() async -> Int {
        await MainActor.run { store.items.filter(\.isOrphan).count }
    }

    // MARK: - Private: feed upload

    private func uploadFeed(config: DriveConfig) async throws {
        guard let folderID = config.folderID else { throw PublisherError.notConnected }

        // Self-heal: if feedFileID is lost (reinstall, Keychain wipe), look up by name
        // before creating a duplicate.
        var effectiveConfig = config
        if effectiveConfig.feedFileID == nil {
            if let foundID = try? await driveClient.findFile(name: "feed.xml", parentID: folderID) {
                AppLogger.publishing.info("uploadFeed: self-healed feedFileID from Drive lookup: \(foundID, privacy: .public)")
                try? await driveClient.setAnyoneWithLink(fileID: foundID)
                effectiveConfig = config.copying(feedFileID: foundID)
                DriveConfig.save(effectiveConfig)
            }
        }

        let items = await buildRSSItems()
        let feedXML = RSSGenerator.render(channel: channel, items: items)
        let feedData = Data(feedXML.utf8)

        if let feedFileID = effectiveConfig.feedFileID {
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
            DriveConfig.save(effectiveConfig.copying(feedFileID: newFeedFileID))
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
