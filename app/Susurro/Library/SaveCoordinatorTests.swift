import Foundation
import Testing
@testable import Susurro

// MARK: - Test doubles

/// A configurable fake for `SourceResolving`.
struct FakeSourceResolver: SourceResolving {
    var resolvedSource: ResolvedSource?
    var clipboardURL: String?

    func resolve() -> ResolvedSource? { resolvedSource }
    func urlFromClipboard() -> String? { clipboardURL }
}

/// A recording fake for `Enqueuing`.
actor FakeEnqueuer: Enqueuing {
    private(set) var enqueuedIDs: [UUID] = []

    func enqueue(itemID: UUID) async {
        enqueuedIDs.append(itemID)
    }
}

// MARK: - Tests

@Suite("SaveCoordinator")
@MainActor
struct SaveCoordinatorTests {

    // MARK: - Helpers

    private func makeTempStore() -> LibraryStore {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = LibraryStore(applicationSupportRoot: tmp)
        store.load()
        return store
    }

    // MARK: - Browser URL

    @Test("browser source → item created with .url kind and enqueued once")
    func browserSourceCreatesURLItem() async {
        let store = makeTempStore()
        let enqueuer = FakeEnqueuer()
        var resolver = FakeSourceResolver()
        resolver.resolvedSource = .browserURL("https://example.com/article")

        let coordinator = SaveCoordinator(store: store, synthesizer: enqueuer, resolver: resolver)
        await coordinator.saveFromFrontmost()

        #expect(store.items.count == 1)
        let item = store.items[0]
        #expect(item.sourceKind == .url)
        #expect(item.sourceURL == "https://example.com/article")
        #expect(item.status == .pending)

        let enqueued = await enqueuer.enqueuedIDs
        #expect(enqueued.count == 1)
        #expect(enqueued[0] == item.id)
    }

    // MARK: - Full text

    @Test("text source with title → .text item uses provided title")
    func textSourceWithTitleUsesProvidedTitle() async {
        let store = makeTempStore()
        let enqueuer = FakeEnqueuer()
        var resolver = FakeSourceResolver()
        resolver.resolvedSource = .fullText(text: "Hello world", title: "My Article")

        let coordinator = SaveCoordinator(store: store, synthesizer: enqueuer, resolver: resolver)
        await coordinator.saveFromFrontmost()

        #expect(store.items.count == 1)
        let item = store.items[0]
        #expect(item.sourceKind == .text)
        #expect(item.rawText == "Hello world")
        #expect(item.title == "My Article")

        let enqueued = await enqueuer.enqueuedIDs
        #expect(enqueued.count == 1)
    }

    @Test("text source with nil title → first-50-chars fallback")
    func textSourceNilTitleUsesFallback() async {
        let store = makeTempStore()
        let enqueuer = FakeEnqueuer()
        let longText = String(repeating: "a", count: 80)
        var resolver = FakeSourceResolver()
        resolver.resolvedSource = .fullText(text: longText, title: nil)

        let coordinator = SaveCoordinator(store: store, synthesizer: enqueuer, resolver: resolver)
        await coordinator.saveFromFrontmost()

        #expect(store.items.count == 1)
        let item = store.items[0]
        #expect(item.title == String(repeating: "a", count: 50) + "…")
    }

    @Test("text source with empty title → first-50-chars fallback")
    func textSourceEmptyTitleUsesFallback() async {
        let store = makeTempStore()
        let enqueuer = FakeEnqueuer()
        var resolver = FakeSourceResolver()
        resolver.resolvedSource = .fullText(text: "Short text", title: "")

        let coordinator = SaveCoordinator(store: store, synthesizer: enqueuer, resolver: resolver)
        await coordinator.saveFromFrontmost()

        #expect(store.items.count == 1)
        // Text is shorter than 50 chars, so no ellipsis.
        #expect(store.items[0].title == "Short text")
    }

    // MARK: - Clipboard fallback

    @Test("nil source + clipboard URL → URL item created and enqueued")
    func nilSourceClipboardFallbackCreatesURLItem() async {
        let store = makeTempStore()
        let enqueuer = FakeEnqueuer()
        var resolver = FakeSourceResolver()
        resolver.resolvedSource = nil
        resolver.clipboardURL = "https://clipboard.example.com"

        let coordinator = SaveCoordinator(store: store, synthesizer: enqueuer, resolver: resolver)
        await coordinator.saveFromFrontmost()

        #expect(store.items.count == 1)
        let item = store.items[0]
        #expect(item.sourceKind == .url)
        #expect(item.sourceURL == "https://clipboard.example.com")

        let enqueued = await enqueuer.enqueuedIDs
        #expect(enqueued.count == 1)
    }

    // MARK: - No source at all

    @Test("nil source + nil clipboard → nothing added to store")
    func nilSourceNilClipboardAddsNothing() async {
        let store = makeTempStore()
        let enqueuer = FakeEnqueuer()
        let resolver = FakeSourceResolver() // both nil by default

        let coordinator = SaveCoordinator(store: store, synthesizer: enqueuer, resolver: resolver)
        await coordinator.saveFromFrontmost()

        #expect(store.items.isEmpty)
        let enqueued = await enqueuer.enqueuedIDs
        #expect(enqueued.isEmpty)
    }
}
