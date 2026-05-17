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
        return id
    }

    func updateFile(fileID: String, data: Data, mimeType: String) async throws {
        calls.append(Call(method: "updateFile", args: [fileID, mimeType]))
    }

    func deleteFile(fileID: String) async throws {
        calls.append(Call(method: "deleteFile", args: [fileID]))
    }

    func setAnyoneWithLink(fileID: String) async throws {
        calls.append(Call(method: "setAnyoneWithLink", args: [fileID]))
    }

    func headFile(fileID: String) async throws -> DriveFileMeta? {
        calls.append(Call(method: "headFile", args: [fileID]))
        return nil
    }

    func callMethods() async -> [String] {
        calls.map { $0.method }
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
}
