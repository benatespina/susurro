import Foundation
import Testing
@testable import Susurro

// MARK: - Test Doubles

struct FakeClock: ClockProviding {
    var now: Date
}

actor FakePublisher: LibraryPublishing {
    private(set) var publishedIDs: [UUID] = []
    private(set) var unpublishedIDs: [UUID] = []
    private(set) var regenerateFeedCallCount: Int = 0
    private(set) var publishOrphansCallCount: Int = 0

    func publish(itemID: UUID) async throws {
        publishedIDs.append(itemID)
    }

    func unpublish(itemID: UUID) async throws {
        unpublishedIDs.append(itemID)
    }

    func regenerateFeed() async throws {
        regenerateFeedCallCount += 1
    }

    func publishOrphans() async {
        publishOrphansCallCount += 1
    }
}

// MARK: - LibraryCleanupTaskTests

@Suite("LibraryCleanupTask")
@MainActor
struct LibraryCleanupTaskTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore(applicationSupportRoot: URL) -> LibraryStore {
        let store = LibraryStore(applicationSupportRoot: applicationSupportRoot)
        store.load()
        return store
    }

    private func playedItem(daysAgo: Double, audioFilename: String? = nil) -> LibraryItem {
        let playedAt = Date(timeIntervalSinceNow: -daysAgo * 86400)
        return LibraryItem(
            id: UUID(),
            createdAt: playedAt,
            title: "Played Item",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .played,
            audioFilename: audioFilename,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: playedAt,
            driveFileID: nil
        )
    }

    private func pendingItem() -> LibraryItem {
        LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: "Pending Item",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
    }

    private func readyItem() -> LibraryItem {
        LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: "Ready Item",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .ready,
            audioFilename: "audio.mp3",
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
    }

    private func archivedItem() -> LibraryItem {
        let playedAt = Date(timeIntervalSinceNow: -90 * 86400)
        return LibraryItem(
            id: UUID(),
            createdAt: playedAt,
            title: "Archived",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .archived,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: playedAt,
            driveFileID: nil
        )
    }

    // MARK: - Tests

    @Test func playedItemOlderThanTTLIsArchived() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let audioDir = dir.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let audioFilename = "test-\(UUID().uuidString).mp3"
        let audioFile = audioDir.appendingPathComponent(audioFilename)
        try Data([0xFF, 0xFB]).write(to: audioFile)

        let item = playedItem(daysAgo: 35, audioFilename: audioFilename)
        store.add(item)

        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()
        let settings = LibrarySettings()
        settings.playedTTLDays = 30

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: audioDir,
            clock: clock,
            fileManager: .default
        )

        await task.runOnce()

        let updated = store.items.first { $0.id == item.id }
        #expect(updated?.status == .archived)
        #expect(updated?.audioFilename == nil)
        #expect(!FileManager.default.fileExists(atPath: audioFile.path))

        let unpublishedIDs = await publisher.unpublishedIDs
        #expect(unpublishedIDs.contains(item.id))
    }

    @Test func playedItemWithinTTLIsUntouched() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let item = playedItem(daysAgo: 5)
        store.add(item)

        let settings = LibrarySettings()
        settings.playedTTLDays = 30
        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: dir,
            clock: clock
        )

        await task.runOnce()

        let updated = store.items.first { $0.id == item.id }
        #expect(updated?.status == .played)

        let regenerateCount = await publisher.regenerateFeedCallCount
        #expect(regenerateCount == 0)
    }

    @Test func pendingItemIsUntouched() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let item = pendingItem()
        store.add(item)

        let settings = LibrarySettings()
        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: dir,
            clock: clock
        )

        await task.runOnce()

        let updated = store.items.first { $0.id == item.id }
        #expect(updated?.status == .pending)
    }

    @Test func readyItemIsUntouched() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let item = readyItem()
        store.add(item)

        let settings = LibrarySettings()
        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: dir,
            clock: clock
        )

        await task.runOnce()

        let updated = store.items.first { $0.id == item.id }
        #expect(updated?.status == .ready)
    }

    @Test func regenerateFeedCalledOnceWhenItemsChanged() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let item1 = playedItem(daysAgo: 40)
        let item2 = playedItem(daysAgo: 45)
        store.add(item1)
        store.add(item2)

        let settings = LibrarySettings()
        settings.playedTTLDays = 30
        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: dir,
            clock: clock
        )

        await task.runOnce()

        let regenerateCount = await publisher.regenerateFeedCallCount
        #expect(regenerateCount == 1)
    }

    @Test func regenerateFeedNotCalledWhenNothingChanged() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let item = pendingItem()
        store.add(item)

        let settings = LibrarySettings()
        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: dir,
            clock: clock
        )

        await task.runOnce()

        let regenerateCount = await publisher.regenerateFeedCallCount
        #expect(regenerateCount == 0)
    }

    @Test func alreadyArchivedItemNotReArchived() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(applicationSupportRoot: dir)
        let item = archivedItem()
        store.add(item)

        let settings = LibrarySettings()
        let clock = FakeClock(now: Date())
        let publisher = FakePublisher()

        let task = LibraryCleanupTask(
            store: store,
            publisher: publisher,
            settings: settings,
            audioDirectoryURL: dir,
            clock: clock
        )

        await task.runOnce()

        let updated = store.items.first { $0.id == item.id }
        #expect(updated?.status == .archived)

        let unpublishedIDs = await publisher.unpublishedIDs
        #expect(!unpublishedIDs.contains(item.id))

        let regenerateCount = await publisher.regenerateFeedCallCount
        #expect(regenerateCount == 0)
    }
}
