import Foundation
import Testing
@testable import Susurro

@Suite("LibraryStore")
@MainActor
struct LibraryStoreTests {

    // MARK: - load() on empty directory

    @Test func loadOnEmptyDirCreatesDirectoriesAndReturnsEmpty() {
        let tmpRoot = makeTempRoot()
        let store = LibraryStore(applicationSupportRoot: tmpRoot)
        store.load()

        let libraryDir = tmpRoot.appending(path: "library")
        let audioDir = tmpRoot.appending(path: "library/audio")
        #expect(FileManager.default.fileExists(atPath: libraryDir.path))
        #expect(FileManager.default.fileExists(atPath: audioDir.path))
        #expect(store.items.isEmpty)
    }

    // MARK: - add + persist + round-trip

    @Test func addPersistsAndReloadRoundTrips() throws {
        let tmpRoot = makeTempRoot()
        let store = LibraryStore(applicationSupportRoot: tmpRoot)
        store.load()

        let item = makeItem(url: "https://example.com/article")
        store.add(item)

        // Fresh store loads from disk
        let store2 = LibraryStore(applicationSupportRoot: tmpRoot)
        store2.load()
        #expect(store2.items.count == 1)
        #expect(store2.items[0].id == item.id)
        #expect(store2.items[0].sourceURL == "https://example.com/article")
        #expect(store2.items[0].status == .pending)
    }

    // MARK: - update mutates in memory and persists

    @Test func updateMutatesInMemoryAndPersists() throws {
        let tmpRoot = makeTempRoot()
        let store = LibraryStore(applicationSupportRoot: tmpRoot)
        store.load()

        let item = makeItem(url: "https://example.com")
        store.add(item)

        store.update(id: item.id) { $0.title = "Updated Title" }

        #expect(store.items[0].title == "Updated Title")

        let store2 = LibraryStore(applicationSupportRoot: tmpRoot)
        store2.load()
        #expect(store2.items[0].title == "Updated Title")
    }

    // MARK: - remove

    @Test func removeDeletesFromItemsAndDisk() throws {
        let tmpRoot = makeTempRoot()
        let store = LibraryStore(applicationSupportRoot: tmpRoot)
        store.load()

        let item = makeItem(url: "https://example.com")
        store.add(item)
        #expect(store.items.count == 1)

        store.remove(id: item.id)
        #expect(store.items.isEmpty)

        let store2 = LibraryStore(applicationSupportRoot: tmpRoot)
        store2.load()
        #expect(store2.items.isEmpty)
    }

    @Test func removeAlsoDeletesAudioFileIfPresent() throws {
        let tmpRoot = makeTempRoot()
        let store = LibraryStore(applicationSupportRoot: tmpRoot)
        store.load()

        // Create a fake audio file
        let audioFilename = UUID().uuidString + ".mp3"
        let audioDir = tmpRoot.appending(path: "library/audio")
        let audioPath = audioDir.appending(path: audioFilename)
        try Data("fake audio".utf8).write(to: audioPath)
        #expect(FileManager.default.fileExists(atPath: audioPath.path))

        var item = makeItem(url: "https://example.com")
        item.audioFilename = audioFilename
        store.add(item)

        store.remove(id: item.id)

        #expect(!FileManager.default.fileExists(atPath: audioPath.path))
    }

    // MARK: - sort order

    @Test func itemsLoadSortedNewestFirst() throws {
        let tmpRoot = makeTempRoot()
        let store = LibraryStore(applicationSupportRoot: tmpRoot)
        store.load()

        let older = makeItem(url: "https://older.com", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeItem(url: "https://newer.com", createdAt: Date(timeIntervalSince1970: 2_000))
        let newest = makeItem(url: "https://newest.com", createdAt: Date(timeIntervalSince1970: 3_000))

        // Add in non-chronological order
        store.add(older)
        store.add(newest)
        store.add(newer)

        // Verify in-memory order
        #expect(store.items[0].sourceURL == "https://newest.com")
        #expect(store.items[1].sourceURL == "https://newer.com")
        #expect(store.items[2].sourceURL == "https://older.com")

        // Load from disk and verify sort is preserved
        let store2 = LibraryStore(applicationSupportRoot: tmpRoot)
        store2.load()
        #expect(store2.items[0].sourceURL == "https://newest.com")
        #expect(store2.items[1].sourceURL == "https://newer.com")
        #expect(store2.items[2].sourceURL == "https://older.com")
    }

    // MARK: - Helpers

    private func makeTempRoot() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeItem(
        url: String,
        createdAt: Date = Date()
    ) -> LibraryItem {
        LibraryItem(
            id: UUID(),
            createdAt: createdAt,
            title: nil,
            sourceURL: url,
            sourceKind: .url,
            rawText: nil,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil
        )
    }
}
