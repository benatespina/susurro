import Foundation
import Testing
@testable import Susurro

// MARK: - Fake DriveUploading

actor FakeDriveClient: DriveUploading {
    struct Call: Sendable, Equatable {
        let method: String
        let args: [String]
    }

    private(set) var calls: [Call] = []
    var uploadedFileIDs: [String: String] = [:]  // name → id
    var feedFileID: String = "feed-file-id"
    var headFileResult: DriveFileMeta? = nil
    var headFileResultsByID: [String: DriveFileMeta] = [:]
    var feedUpdateShouldThrow: Bool = false

    func createFolder(name: String, parentID: String) async throws -> String {
        calls.append(Call(method: "createFolder", args: [name, parentID]))
        return "folder-\(name)"
    }

    func uploadFile(name: String, mimeType: String, data: Data, parentID: String) async throws -> String {
        calls.append(Call(method: "uploadFile", args: [name, mimeType, parentID]))
        if name.hasSuffix(".xml") {
            return feedFileID
        }
        let id = uploadedFileIDs[name] ?? "file-\(name)"
        // Auto-register so subsequent headFile calls see this file as existing.
        headFileResultsByID[id] = DriveFileMeta(id: id, name: name, size: Int64(data.count), mimeType: mimeType)
        return id
    }

    func updateFile(fileID: String, data: Data, mimeType: String) async throws {
        calls.append(Call(method: "updateFile", args: [fileID, mimeType]))
        if feedUpdateShouldThrow {
            struct FeedUpdateError: Error {}
            throw FeedUpdateError()
        }
    }

    func deleteFile(fileID: String) async throws {
        calls.append(Call(method: "deleteFile", args: [fileID]))
    }

    func setAnyoneWithLink(fileID: String) async throws {
        calls.append(Call(method: "setAnyoneWithLink", args: [fileID]))
    }

    func headFile(fileID: String) async throws -> DriveFileMeta? {
        calls.append(Call(method: "headFile", args: [fileID]))
        return headFileResultsByID[fileID] ?? headFileResult
    }

    func callMethods() async -> [String] {
        calls.map { $0.method }
    }

    func setHeadFileResult(_ result: DriveFileMeta?) {
        headFileResult = result
    }

    func setHeadFileResult(_ result: DriveFileMeta?, forID fileID: String) {
        headFileResultsByID[fileID] = result
    }

    func setFeedUpdateShouldThrow(_ value: Bool) {
        feedUpdateShouldThrow = value
    }
}

// MARK: - Helpers

@MainActor
private func makeStore() -> LibraryStore {
    // Use a temp directory so tests don't pollute ~/Library/Application Support/Susurro.
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("SusurroTests-\(UUID().uuidString)")
    return LibraryStore(applicationSupportRoot: tempRoot)
}

private func makeChannel() -> RSSChannel {
    RSSChannel(
        title: "Susurro Library",
        description: "Articles saved with Susurro",
        link: URL(string: "https://example.com/feed")!,
        language: "es-ES",
        imageURL: nil,
        author: "Susurro"
    )
}

@MainActor
private func addReadyItemWithAudio(to store: LibraryStore, id: UUID, tempDir: URL) throws -> LibraryItem {
    let item = LibraryItem(
        id: id,
        createdAt: Date(),
        title: "Test Article",
        sourceURL: "https://example.com/article",
        sourceKind: .url,
        rawText: nil,
        status: .ready,
        audioFilename: "\(id.uuidString).mp3",
        durationSeconds: 120,
        byteSize: 9876,
        lastError: nil,
        playedAt: nil,
        driveFileID: nil
    )
    // Write a fake MP3 to the temp audio dir.
    let audioURL = tempDir.appendingPathComponent("\(id.uuidString).mp3")
    try Data("fake mp3 data".utf8).write(to: audioURL)

    store.add(item)
    return item
}

@Suite("LibraryPublisher", .serialized)
@MainActor
struct LibraryPublisherTests {

    // MARK: - Happy path: publish

    @Test func publishHappyPathRecordsCallsInOrder() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()
        let itemID = UUID()
        _ = try addReadyItemWithAudio(to: store, id: itemID, tempDir: tempDir)

        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: nil
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        try await publisher.publish(itemID: itemID)

        let methods = await fakeClient.callMethods()
        // Expected order: uploadFile(mp3), setAnyoneWithLink(mp3), uploadFile(feed), setAnyoneWithLink(feed)
        #expect(methods.count == 4)
        #expect(methods[0] == "uploadFile")           // mp3
        #expect(methods[1] == "setAnyoneWithLink")    // mp3 file
        #expect(methods[2] == "uploadFile")           // feed.xml (no feedFileID yet)
        #expect(methods[3] == "setAnyoneWithLink")    // feed.xml
    }

    @Test func publishNoFolderIDThrowsNotConnected() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()
        let itemID = UUID()
        _ = try addReadyItemWithAudio(to: store, id: itemID, tempDir: tempDir)

        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: nil,  // No folder configured
                    feedFileID: nil
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        do {
            try await publisher.publish(itemID: itemID)
            Issue.record("Expected notConnected error")
        } catch PublisherError.notConnected {
            // Expected.
        }

        // Item status should be set to failed.
        let updatedItem = store.items.first { $0.id == itemID }
        if case .failed = updatedItem?.status { /* ok */ } else {
            Issue.record("Expected item status to be .failed")
        }
    }

    @Test func subsequentPublishReuseFeedFileID() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()
        let itemID = UUID()
        _ = try addReadyItemWithAudio(to: store, id: itemID, tempDir: tempDir)

        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-file-id"  // Already exists
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        try await publisher.publish(itemID: itemID)

        let methods = await fakeClient.callMethods()
        // uploadFile(mp3), setAnyoneWithLink(mp3), updateFile(feed) — NOT uploadFile for feed
        let uploadFileCalls = methods.filter { $0 == "uploadFile" }
        let updateFileCalls = methods.filter { $0 == "updateFile" }
        #expect(uploadFileCalls.count == 1)  // only mp3
        #expect(updateFileCalls.count == 1)  // feed update (not upload)
    }

    // MARK: - Unpublish

    @Test func unpublishCallsDeleteFileAndRegeneratesFeed() async throws {
        let store = makeStore()
        let itemID = UUID()
        let item = LibraryItem(
            id: itemID,
            createdAt: Date(),
            title: "Article",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .ready,
            audioFilename: "\(itemID.uuidString).mp3",
            durationSeconds: 60,
            byteSize: 1234,
            lastError: nil,
            playedAt: nil,
            driveFileID: "drive-file-123"
        )
        store.add(item)

        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "feed-file-id"
                )
            },
            channel: makeChannel()
        )

        try await publisher.unpublish(itemID: itemID)

        let methods = await fakeClient.callMethods()
        // deleteFile(mp3), updateFile(feed) — feed regenerated
        #expect(methods.contains("deleteFile"))
        #expect(methods.contains("updateFile"))

        // driveFileID should be cleared.
        let updatedItem = store.items.first { $0.id == itemID }
        #expect(updatedItem?.driveFileID == nil)
    }

    // MARK: - regenerateFeed

    @Test func regenerateFeedUpdatesExistingFeedFile() async throws {
        let store = makeStore()
        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"
                )
            },
            channel: makeChannel()
        )

        try await publisher.regenerateFeed()

        let methods = await fakeClient.callMethods()
        #expect(methods == ["updateFile"])
    }

    // MARK: - publishOrphans

    @Test func publishOrphansBackPublishesReadyItemsWithoutDriveFileID() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()

        // 2 orphans: .ready, audioFilename set, driveFileID nil
        let orphan1ID = UUID()
        let orphan2ID = UUID()
        _ = try addReadyItemWithAudio(to: store, id: orphan1ID, tempDir: tempDir)
        _ = try addReadyItemWithAudio(to: store, id: orphan2ID, tempDir: tempDir)

        // 1 already-published item: .ready, driveFileID set
        let publishedID = UUID()
        let publishedItem = LibraryItem(
            id: publishedID,
            createdAt: Date(),
            title: "Published",
            sourceURL: "https://example.com/pub",
            sourceKind: .url,
            rawText: nil,
            status: .ready,
            audioFilename: "\(publishedID.uuidString).mp3",
            durationSeconds: 60,
            byteSize: 1234,
            lastError: nil,
            playedAt: nil,
            driveFileID: "existing-drive-id"
        )
        store.add(publishedItem)

        // 1 pending item
        let pendingItem = LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: "Pending",
            sourceURL: nil,
            sourceKind: .text,
            rawText: "some text",
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
        store.add(pendingItem)

        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        await publisher.publishOrphans()

        let calls = await fakeClient.calls
        let mp3Uploads = calls.filter { $0.method == "uploadFile" && $0.args.contains("audio/mpeg") }
        // Only 2 orphans should upload an MP3
        #expect(mp3Uploads.count == 2)

        // The already-published item should NOT have triggered an uploadFile for its file
        let uploadArgs = mp3Uploads.flatMap { $0.args }
        #expect(!uploadArgs.contains("\(publishedID.uuidString).mp3"))

        // The already-published item should NOT have triggered a headFile call —
        // publishOrphans filters by isOrphan (driveFileID == nil), so it never calls publish() for it.
        let headFileCalls = calls.filter { $0.method == "headFile" }
        let headFileArgs = headFileCalls.flatMap { $0.args }
        #expect(!headFileArgs.contains("existing-drive-id"))

        // Orphans should now have driveFileID set
        let updatedOrphan1 = store.items.first { $0.id == orphan1ID }
        let updatedOrphan2 = store.items.first { $0.id == orphan2ID }
        #expect(updatedOrphan1?.driveFileID != nil)
        #expect(updatedOrphan2?.driveFileID != nil)
    }

    // MARK: - Idempotency: skip MP3 upload when headFile confirms existing

    @Test func publishSkipsMP3UploadWhenDriveFileIDExistsAndHeadFileSucceeds() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()
        let itemID = UUID()

        // Item already has a driveFileID
        let item = LibraryItem(
            id: itemID,
            createdAt: Date(),
            title: "Already Uploaded",
            sourceURL: "https://example.com/article",
            sourceKind: .url,
            rawText: nil,
            status: .ready,
            audioFilename: "\(itemID.uuidString).mp3",
            durationSeconds: 120,
            byteSize: 9876,
            lastError: nil,
            playedAt: nil,
            driveFileID: "existing-id"
        )
        // Write audio file in case it falls through (shouldn't be read)
        let audioURL = tempDir.appendingPathComponent("\(itemID.uuidString).mp3")
        try Data("fake mp3 data".utf8).write(to: audioURL)
        store.add(item)

        let fakeClient = FakeDriveClient()
        // headFile returns a valid DriveFileMeta, meaning the file exists on Drive
        await fakeClient.setHeadFileResult(DriveFileMeta(id: "existing-id", name: "\(itemID.uuidString).mp3", size: 9876, mimeType: "audio/mpeg"))

        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        try await publisher.publish(itemID: itemID)

        let calls = await fakeClient.calls
        let mp3Uploads = calls.filter { $0.method == "uploadFile" && $0.args.contains("audio/mpeg") }
        // No MP3 upload should have occurred
        #expect(mp3Uploads.isEmpty)

        // driveFileID unchanged
        let updatedItem = store.items.first { $0.id == itemID }
        #expect(updatedItem?.driveFileID == "existing-id")
        #expect(updatedItem?.status == .ready)
    }

    // MARK: - Feed failure leaves item .ready

    @Test func feedUploadFailureLeavesItemAsReadyAndPublished() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()
        let itemID = UUID()
        _ = try addReadyItemWithAudio(to: store, id: itemID, tempDir: tempDir)

        let fakeClient = FakeDriveClient()
        // Feed update will throw
        await fakeClient.setFeedUpdateShouldThrow(true)

        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"  // triggers updateFile path
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        // Should NOT throw even though feed update fails
        try await publisher.publish(itemID: itemID)

        // MP3 was uploaded
        let calls = await fakeClient.calls
        let mp3Uploads = calls.filter { $0.method == "uploadFile" && $0.args.contains("audio/mpeg") }
        #expect(mp3Uploads.count == 1)

        // Item driveFileID is set
        let updatedItem = store.items.first { $0.id == itemID }
        #expect(updatedItem?.driveFileID != nil)

        // Item status is .ready, NOT .failed
        #expect(updatedItem?.status == .ready)
    }

    // MARK: - reconcileMissing

    @Test func reconcileMissingRePublishesItemsWhoseDriveFileIsGone() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()

        // 3 items with driveFileID and audio on disk.
        let id1 = UUID(); let id2 = UUID(); let id3 = UUID()
        for id in [id1, id2, id3] {
            let audioURL = tempDir.appendingPathComponent("\(id.uuidString).mp3")
            try Data("fake mp3 data".utf8).write(to: audioURL)
            store.add(LibraryItem(
                id: id,
                createdAt: Date(),
                title: "Article",
                sourceURL: "https://example.com/\(id.uuidString)",
                sourceKind: .url,
                rawText: nil,
                status: .ready,
                audioFilename: "\(id.uuidString).mp3",
                durationSeconds: 60,
                byteSize: 1234,
                lastError: nil,
                playedAt: nil,
                driveFileID: "id-\(id.uuidString)"
            ))
        }

        let fakeClient = FakeDriveClient()
        // id1 exists on Drive; id2 and id3 do not.
        await fakeClient.setHeadFileResult(
            DriveFileMeta(id: "id-\(id1.uuidString)", name: "\(id1.uuidString).mp3", size: 1234, mimeType: "audio/mpeg"),
            forID: "id-\(id1.uuidString)"
        )
        // id2 and id3 return nil (missing).

        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        let count = await publisher.reconcileMissing()

        // Should have re-published id2 and id3.
        #expect(count == 2)

        // id2 and id3 should now have new (non-nil) driveFileIDs.
        let updated2 = store.items.first { $0.id == id2 }
        let updated3 = store.items.first { $0.id == id3 }
        #expect(updated2?.driveFileID != nil)
        #expect(updated3?.driveFileID != nil)

        // id1 should be untouched.
        let updated1 = store.items.first { $0.id == id1 }
        #expect(updated1?.driveFileID == "id-\(id1.uuidString)")

        // Verify mp3 uploadFile calls only for id2 and id3.
        let calls = await fakeClient.calls
        let mp3Uploads = calls.filter { $0.method == "uploadFile" && $0.args.contains("audio/mpeg") }
        #expect(mp3Uploads.count == 2)
        let uploadedNames = mp3Uploads.flatMap { $0.args }
        #expect(!uploadedNames.contains("\(id1.uuidString).mp3"))
    }

    @Test func reconcileMissingSkipsWhenDriveNotConfigured() async throws {
        let store = makeStore()
        store.add(LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: "Article",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .ready,
            audioFilename: "audio.mp3",
            durationSeconds: 60,
            byteSize: 1234,
            lastError: nil,
            playedAt: nil,
            driveFileID: "some-drive-id"
        ))

        let fakeClient = FakeDriveClient()
        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: { nil },  // Drive not configured
            channel: makeChannel()
        )

        let count = await publisher.reconcileMissing()

        #expect(count == 0)
        let calls = await fakeClient.calls
        #expect(calls.isEmpty)
    }

    // MARK: - sync

    @Test func syncCombinesOrphansAndReconcileWithSingleFeedRegen() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = makeStore()

        // 1 orphan: .ready, driveFileID nil, audio on disk.
        let orphanID = UUID()
        _ = try addReadyItemWithAudio(to: store, id: orphanID, tempDir: tempDir)

        // 1 missing: .ready, driveFileID set, headFile returns nil, audio on disk.
        let missingID = UUID()
        let missingDriveID = "missing-drive-id"
        let missingAudioURL = tempDir.appendingPathComponent("\(missingID.uuidString).mp3")
        try Data("fake mp3 data".utf8).write(to: missingAudioURL)
        store.add(LibraryItem(
            id: missingID,
            createdAt: Date(),
            title: "Missing",
            sourceURL: "https://example.com/missing",
            sourceKind: .url,
            rawText: nil,
            status: .ready,
            audioFilename: "\(missingID.uuidString).mp3",
            durationSeconds: 60,
            byteSize: 1234,
            lastError: nil,
            playedAt: nil,
            driveFileID: missingDriveID
        ))

        // 1 valid: .ready, driveFileID set, headFile returns non-nil.
        let validID = UUID()
        let validDriveID = "valid-drive-id"
        store.add(LibraryItem(
            id: validID,
            createdAt: Date(),
            title: "Valid",
            sourceURL: "https://example.com/valid",
            sourceKind: .url,
            rawText: nil,
            status: .ready,
            audioFilename: "\(validID.uuidString).mp3",
            durationSeconds: 60,
            byteSize: 1234,
            lastError: nil,
            playedAt: nil,
            driveFileID: validDriveID
        ))

        let fakeClient = FakeDriveClient()
        // valid item exists on Drive; missing item does not.
        await fakeClient.setHeadFileResult(
            DriveFileMeta(id: validDriveID, name: "\(validID.uuidString).mp3", size: 1234, mimeType: "audio/mpeg"),
            forID: validDriveID
        )
        // missingDriveID returns nil by default.

        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"
                )
            },
            channel: makeChannel(),
            audioDirectory: tempDir
        )

        let summary = await publisher.sync()

        #expect(summary.orphansPublished == 1)
        #expect(summary.missingRePublished == 1)
        #expect(summary.feedRegenerated == true)

        // Exactly 1 feed-related call (updateFile with rss+xml, since feedFileID is set).
        let calls = await fakeClient.calls
        let feedCalls = calls.filter {
            ($0.method == "uploadFile" || $0.method == "updateFile") && $0.args.contains("application/rss+xml")
        }
        #expect(feedCalls.count == 1)
    }

    @Test func syncSkipsFeedRegenWhenNothingChanged() async throws {
        let store = makeStore()

        // 1 valid item only: .ready, driveFileID set, headFile returns non-nil.
        let validID = UUID()
        let validDriveID = "valid-drive-id"
        store.add(LibraryItem(
            id: validID,
            createdAt: Date(),
            title: "Valid",
            sourceURL: "https://example.com/valid",
            sourceKind: .url,
            rawText: nil,
            status: .ready,
            audioFilename: "\(validID.uuidString).mp3",
            durationSeconds: 60,
            byteSize: 1234,
            lastError: nil,
            playedAt: nil,
            driveFileID: validDriveID
        ))

        let fakeClient = FakeDriveClient()
        await fakeClient.setHeadFileResult(
            DriveFileMeta(id: validDriveID, name: "\(validID.uuidString).mp3", size: 1234, mimeType: "audio/mpeg"),
            forID: validDriveID
        )

        let publisher = LibraryPublisher(
            store: store,
            driveClient: fakeClient,
            configProvider: {
                DriveConfig(
                    clientID: "cid", clientSecret: "cs",
                    refreshToken: "rt", accessToken: "at",
                    accessTokenExpiry: Date().addingTimeInterval(3600),
                    folderID: "folder-id",
                    feedFileID: "existing-feed-id"
                )
            },
            channel: makeChannel()
        )

        let summary = await publisher.sync()

        #expect(summary.orphansPublished == 0)
        #expect(summary.missingRePublished == 0)
        #expect(summary.feedRegenerated == false)

        // No feed-related calls.
        let calls = await fakeClient.calls
        let feedCalls = calls.filter {
            ($0.method == "uploadFile" || $0.method == "updateFile") && $0.args.contains("application/rss+xml")
        }
        #expect(feedCalls.isEmpty)
    }
}
