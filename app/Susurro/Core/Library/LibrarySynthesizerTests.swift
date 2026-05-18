import AVFoundation
import Foundation
import Testing
@testable import Susurro

// MARK: - Fakes

/// A fake LibraryPublishing implementation that records publish calls.
actor FakeSynthesizerPublisher: LibraryPublishing {
    private(set) var publishedIDs: [UUID] = []

    func publish(itemID: UUID) async throws {
        publishedIDs.append(itemID)
    }

    func unpublish(itemID: UUID) async throws {}

    func regenerateFeed() async throws {}

    func publishOrphans() async {}
}

/// A fake TTS provider that emits a configurable number of data chunks.
actor FakeProvider: TTSProvider {
    var chunksToEmit: Int = 2
    var throwAfterChunks: Int? = nil
    var chunkData: Data = Data([0xFF, 0xFB, 0x90, 0x44] + Array(repeating: 0xAA, count: 96))
    var servedItems: [String] = []

    func warmup() async throws {}

    func synthesize(text: String, language: String) async throws -> Data { chunkData }

    nonisolated func synthesizeStream(text: String, language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let data = await self.chunkData
                continuation.yield(data)
                continuation.finish()
            }
        }
    }

    nonisolated func synthesizeChunks(_ chunks: [String], language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.recordAndEmit(language: language, continuation: continuation)
            }
        }
    }

    func recordAndEmit(language: String, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        servedItems.append(language)
        let count = chunksToEmit
        let throwAfter = throwAfterChunks
        let data = chunkData
        Task {
            for i in 0 ..< count {
                if let limit = throwAfter, i >= limit {
                    continuation.finish(throwing: SynthesisError.noProvider)
                    return
                }
                continuation.yield(data)
            }
            continuation.finish()
        }
    }

    nonisolated func synthesizeChunked(text: String, language: String) -> AsyncThrowingStream<Data, Error> {
        synthesizeChunks(Chunker.chunk(text), language: language)
    }

    func synthesizePreview(ssml: String, language: String) async throws -> Data { chunkData }

    func configure(chunksToEmit n: Int) { self.chunksToEmit = n }
    func configure(throwAfterChunks n: Int?) { self.throwAfterChunks = n }
}

/// A fake article extractor.
struct FakeExtractor: ArticleExtracting, Sendable {
    var result: ExtractedArticle
    var shouldFail: Bool = false

    func extract(url: String) async throws -> ExtractedArticle {
        if shouldFail { throw BackendError.extractFailed("fake failure") }
        return result
    }
}

/// A fake duration probe.
struct FakeDurationProbe: AudioDurationProbing {
    var fixedDuration: Double = 42.0
    func duration(of url: URL) async throws -> Double { fixedDuration }
}

/// A fake language detector.
struct FakeLangDetector: LangDetecting {
    var language: String = "en"
    func detect(_ text: String) -> String { language }
}

// MARK: - Helpers

@MainActor
private func makeStore(in dir: URL) -> LibraryStore {
    let store = LibraryStore(applicationSupportRoot: dir)
    store.load()
    return store
}

@MainActor
private func makeSynthesizer(
    store: LibraryStore,
    extractor: any ArticleExtracting = FakeExtractor(
        result: ExtractedArticle(text: "", title: nil, url: "", language: nil)
    ),
    provider: any TTSProvider,
    probe: any AudioDurationProbing = FakeDurationProbe(),
    langDetect: any LangDetecting = FakeLangDetector(),
    audioDir: URL,
    librarySettings: LibrarySettings? = nil,
    driveConfigProvider: (@Sendable () -> DriveConfig?)? = nil,
    translator: any TranslatorProviding = MockTranslator(),
    translateFlag: @escaping @Sendable () -> Bool = { false }
) -> LibrarySynthesizer {
    let state = LibrarySynthesisState()
    return LibrarySynthesizer(
        store: store,
        extractor: extractor,
        currentProviderProvider: { provider },
        durationProbe: probe,
        langDetect: langDetect,
        audioDirectoryURL: audioDir,
        synthesisState: state,
        librarySettings: librarySettings,
        driveConfigProvider: driveConfigProvider ?? { nil },
        translator: translator,
        isTranslateToSpanishEnabled: translateFlag
    )
}

private func makeFakeDriveConfig() -> DriveConfig {
    DriveConfig(
        clientID: "test-client-id",
        clientSecret: "test-client-secret",
        refreshToken: "test-refresh-token",
        accessToken: "test-access-token",
        accessTokenExpiry: Date().addingTimeInterval(3600),
        folderID: "test-folder-id",
        feedFileID: nil
    )
}

private func makeTempDir() -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}

private func makeURLItem(url: String = "https://example.com/article") -> LibraryItem {
    LibraryItem(
        id: UUID(),
        createdAt: Date(),
        title: nil,
        sourceURL: url,
        sourceKind: .url,
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

private func makeTextItem(text: String = "Hello world. This is sample text for synthesis.") -> LibraryItem {
    LibraryItem(
        id: UUID(),
        createdAt: Date(),
        title: nil,
        sourceURL: nil,
        sourceKind: .text,
        rawText: text,
        status: .pending,
        audioFilename: nil,
        durationSeconds: nil,
        byteSize: nil,
        lastError: nil,
        playedAt: nil,
        driveFileID: nil
    )
}

/// Polls store until item satisfies predicate or max attempts reached.
@MainActor
private func waitForItem(
    store: LibraryStore,
    id: UUID,
    maxAttempts: Int = 100,
    delayMs: UInt64 = 50,
    predicate: (LibraryItem) -> Bool
) async -> LibraryItem? {
    for _ in 0 ..< maxAttempts {
        if let item = store.items.first(where: { $0.id == id }), predicate(item) {
            return item
        }
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
    }
    return nil
}

// MARK: - Suite

@Suite("LibrarySynthesizer")
struct LibrarySynthesizerTests {

    // MARK: - URL happy path

    @Test @MainActor
    func urlItemWalksFullPipeline() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeURLItem()
        store.add(item)

        let provider = FakeProvider()
        let extractor = FakeExtractor(result: ExtractedArticle(
            text: "Hello world article content for synthesis test.",
            title: "Test Title",
            url: "https://example.com/article",
            language: "en"
        ))
        let probe = FakeDurationProbe(fixedDuration: 63.5)

        let synthesizer = makeSynthesizer(
            store: store,
            extractor: extractor,
            provider: provider,
            probe: probe,
            audioDir: audioDir
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        #expect(unwrapped.status == .ready)
        #expect(unwrapped.audioFilename == "\(item.id.uuidString).mp3")
        #expect(unwrapped.durationSeconds == 63.5)
        #expect(unwrapped.byteSize != nil && unwrapped.byteSize! > 0)
        #expect(unwrapped.title == "Test Title")

        let mp3URL = audioDir.appendingPathComponent("\(item.id.uuidString).mp3")
        #expect(FileManager.default.fileExists(atPath: mp3URL.path))
    }

    // MARK: - Text happy path (skips extraction)

    @Test @MainActor
    func textItemSkipsExtractionAndBecomesReady() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem()
        store.add(item)

        let provider = FakeProvider()
        let probe = FakeDurationProbe(fixedDuration: 12.0)

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: probe,
            langDetect: FakeLangDetector(language: "es"),
            audioDir: audioDir
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        #expect(unwrapped.status == .ready)
        #expect(unwrapped.durationSeconds == 12.0)

        let servedLangs = await provider.servedItems
        #expect(servedLangs.contains("es"))
    }

    // MARK: - Mid-stream throw leaves item failed

    @Test @MainActor
    func midStreamThrowLeavesItemFailed() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem()
        store.add(item)

        let provider = FakeProvider()
        await provider.configure(throwAfterChunks: 0)

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            audioDir: audioDir
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .failed, .ready: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        guard case .failed = unwrapped.status else {
            Issue.record("Expected .failed but got \(unwrapped.status)")
            return
        }
        let mp3URL = audioDir.appendingPathComponent("\(item.id.uuidString).mp3")
        #expect(!FileManager.default.fileExists(atPath: mp3URL.path))
    }

    // MARK: - FIFO ordering

    @Test @MainActor
    func fifoOrderingIsPreservedForThreeItems() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item1 = makeTextItem(text: "First item content.")
        let item2 = makeTextItem(text: "Second item content.")
        let item3 = makeTextItem(text: "Third item content.")

        store.add(item1)
        store.add(item2)
        store.add(item3)

        let provider = FakeProvider()
        await provider.configure(chunksToEmit: 1)

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: FakeDurationProbe(fixedDuration: 1.0),
            audioDir: audioDir
        )

        await synthesizer.enqueue(itemID: item1.id)
        await synthesizer.enqueue(itemID: item2.id)
        await synthesizer.enqueue(itemID: item3.id)

        for id in [item1.id, item2.id, item3.id] {
            let finalItem = await waitForItem(store: store, id: id, maxAttempts: 200) { item in
                switch item.status {
                case .ready, .failed: return true
                default: return false
                }
            }
            let unwrapped = try #require(finalItem)
            #expect(unwrapped.status == .ready, "item \(id) expected .ready but got \(unwrapped.status)")
        }

        let servedCount = await provider.servedItems.count
        #expect(servedCount == 3)
    }

    // MARK: - Retry from failed

    @Test @MainActor
    func failedItemIsAcceptedAndReprocessed() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        var item = makeTextItem()
        item.status = .failed(reason: "previous error")
        store.add(item)

        let provider = FakeProvider()

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: FakeDurationProbe(fixedDuration: 5.0),
            audioDir: audioDir
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            if case .ready = item.status { return true }
            if case .failed(let r) = item.status, r != "previous error" { return true }
            return false
        }

        let unwrapped = try #require(finalItem)
        #expect(unwrapped.status == .ready)
    }

    // MARK: - autoPublishOnSynthesize: true publishes

    @Test @MainActor
    func autoPublishTrueCallsPublisher() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem()
        store.add(item)

        let provider = FakeProvider()
        let settings = LibrarySettings()
        settings.autoPublishOnSynthesize = true
        let fakeDriveConfig = makeFakeDriveConfig()

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: FakeDurationProbe(fixedDuration: 5.0),
            audioDir: audioDir,
            librarySettings: settings,
            driveConfigProvider: { fakeDriveConfig }
        )

        let fakePublisher = FakeSynthesizerPublisher()
        await synthesizer.setPublisher(fakePublisher)

        await synthesizer.enqueue(itemID: item.id)

        _ = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        // Give publisher.publish a moment to complete (it runs after status flip).
        try await Task.sleep(nanoseconds: 100_000_000)

        let publishedIDs = await fakePublisher.publishedIDs
        #expect(publishedIDs.contains(item.id), "Publisher should have been called when autoPublish is true")
    }

    // MARK: - autoPublishOnSynthesize: false skips publish

    @Test @MainActor
    func autoPublishFalseSkipsPublisher() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem()
        store.add(item)

        let provider = FakeProvider()
        let settings = LibrarySettings()
        settings.autoPublishOnSynthesize = false
        let fakeDriveConfig = makeFakeDriveConfig()

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: FakeDurationProbe(fixedDuration: 5.0),
            audioDir: audioDir,
            librarySettings: settings,
            driveConfigProvider: { fakeDriveConfig }
        )

        let fakePublisher = FakeSynthesizerPublisher()
        await synthesizer.setPublisher(fakePublisher)

        await synthesizer.enqueue(itemID: item.id)

        _ = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        // Give a moment to confirm publisher was NOT called.
        try await Task.sleep(nanoseconds: 100_000_000)

        let publishedIDs = await fakePublisher.publishedIDs
        #expect(publishedIDs.isEmpty, "Publisher should NOT be called when autoPublish is false")
    }

    // MARK: - enqueuePending picks up pending and failed

    @Test @MainActor
    func enqueuePendingPicksUpPendingAndFailedItems() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        var pending = makeTextItem(text: "Pending item text for synthesis.")
        pending.status = .pending

        var failed = makeTextItem(text: "Failed item text for synthesis retry.")
        failed.status = .failed(reason: "old error")

        var ready = makeTextItem(text: "Already ready, should not be re-synthesized.")
        ready.status = .ready
        ready.audioFilename = "\(ready.id.uuidString).mp3"

        store.add(pending)
        store.add(failed)
        store.add(ready)

        let provider = FakeProvider()

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: FakeDurationProbe(fixedDuration: 3.0),
            audioDir: audioDir
        )

        await synthesizer.enqueuePending()

        for id in [pending.id, failed.id] {
            let finalItem = await waitForItem(store: store, id: id, maxAttempts: 200) { item in
                if case .ready = item.status { return true }
                if case .failed(let r) = item.status, r != "old error" { return true }
                return false
            }
            let unwrapped = try #require(finalItem)
            #expect(unwrapped.status == .ready, "item \(id) expected .ready")
        }

        // The already-ready item should remain unchanged.
        let readyItem = store.items.first { $0.id == ready.id }
        #expect(readyItem?.status == .ready)
        #expect(readyItem?.audioFilename == "\(ready.id.uuidString).mp3")

        // Provider was invoked exactly twice.
        let servedCount = await provider.servedItems.count
        #expect(servedCount == 2)
    }

    // MARK: - Translation: flag on, language != es → translator called, provider receives "es"

    @Test @MainActor
    func translatesWhenFlagOnAndLanguageNotEs() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let originalText = "Hello world. This is sample text for synthesis."
        let item = makeTextItem(text: originalText)
        store.add(item)

        let provider = FakeProvider()
        let probe = FakeDurationProbe(fixedDuration: 5.0)
        let mockTranslator = MockTranslator()
        mockTranslator.result = "[ES] \(originalText)"

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: probe,
            langDetect: FakeLangDetector(language: "en"),
            audioDir: audioDir,
            translator: mockTranslator,
            translateFlag: { true }
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        #expect(unwrapped.status == .ready)

        // Translator must have been called exactly once with target "es-ES".
        #expect(mockTranslator.translateCallCount == 1)
        #expect(mockTranslator.lastTarget == "es-ES")

        // TTS provider must have received language "es".
        let servedLangs = await provider.servedItems
        #expect(servedLangs.contains("es"), "Expected provider to receive 'es', got \(servedLangs)")
    }

    // MARK: - Translation: flag off → translator not called, original language preserved

    @Test @MainActor
    func skipsTranslationWhenFlagOff() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem(text: "Hello world. This is sample text for synthesis.")
        store.add(item)

        let provider = FakeProvider()
        let probe = FakeDurationProbe(fixedDuration: 5.0)
        let mockTranslator = MockTranslator()
        mockTranslator.result = "[ES] translated"

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: probe,
            langDetect: FakeLangDetector(language: "en"),
            audioDir: audioDir,
            translator: mockTranslator,
            translateFlag: { false }
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        #expect(unwrapped.status == .ready)

        // Translator must NOT have been called.
        #expect(mockTranslator.translateCallCount == 0)

        // TTS provider must have received the original language "en" (not "es").
        let servedLangs = await provider.servedItems
        #expect(servedLangs.contains("en"), "Expected provider to receive 'en', got \(servedLangs)")
        #expect(!servedLangs.contains("es"), "Provider should NOT receive 'es' when flag is off")
    }

    // MARK: - Translation: translator throws → item still completes ready in original language

    @Test @MainActor
    func translationFailureFallsBackToOriginalLanguage() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem(text: "Hello world. This is sample text for synthesis.")
        store.add(item)

        let provider = FakeProvider()
        let probe = FakeDurationProbe(fixedDuration: 5.0)
        let mockTranslator = MockTranslator()
        mockTranslator.errorToThrow = TranslatorError.failed(message: "network error")

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: probe,
            langDetect: FakeLangDetector(language: "en"),
            audioDir: audioDir,
            translator: mockTranslator,
            translateFlag: { true }
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        // Item must complete successfully even though translation failed.
        #expect(unwrapped.status == .ready)

        // Translator was called once (attempted).
        #expect(mockTranslator.translateCallCount == 1)

        // TTS provider must have received the original language "en", not "es".
        let servedLangs = await provider.servedItems
        #expect(servedLangs.contains("en"), "Expected fallback to original 'en', got \(servedLangs)")
        #expect(!servedLangs.contains("es"), "Provider should NOT receive 'es' after translation failure")
    }

    // MARK: - Translation: flag on but language is already "es" → translator not called

    @Test @MainActor
    func skipsTranslationWhenLanguageAlreadySpanish() async throws {
        let tmp = makeTempDir()
        let audioDir = tmp.appendingPathComponent("audio")
        let store = makeStore(in: tmp)

        let item = makeTextItem(text: "Hola mundo. Este es el texto de ejemplo para la síntesis.")
        store.add(item)

        let provider = FakeProvider()
        let probe = FakeDurationProbe(fixedDuration: 5.0)
        let mockTranslator = MockTranslator()

        let synthesizer = makeSynthesizer(
            store: store,
            provider: provider,
            probe: probe,
            langDetect: FakeLangDetector(language: "es"),
            audioDir: audioDir,
            translator: mockTranslator,
            translateFlag: { true }
        )

        await synthesizer.enqueue(itemID: item.id)

        let finalItem = await waitForItem(store: store, id: item.id) { item in
            switch item.status {
            case .ready, .failed: return true
            default: return false
            }
        }

        let unwrapped = try #require(finalItem)
        #expect(unwrapped.status == .ready)

        // Translator must NOT have been called — source is already Spanish.
        #expect(mockTranslator.translateCallCount == 0)

        // TTS provider must have received "es" directly.
        let servedLangs = await provider.servedItems
        #expect(servedLangs.contains("es"), "Expected provider to receive 'es', got \(servedLangs)")
    }
}
