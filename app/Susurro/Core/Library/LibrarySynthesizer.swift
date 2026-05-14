import Foundation
import Observation
import os

// MARK: - Protocol abstractions for dependency injection

/// Wraps article extraction so tests can inject fakes.
protocol ArticleExtracting: Sendable {
    func extract(url: String) async throws -> ExtractedArticle
}

extension ArticleExtractor: ArticleExtracting {}

/// Wraps language detection so tests can inject fakes.
protocol LangDetecting: Sendable {
    func detect(_ text: String) -> String
}

/// Production implementation that delegates to `LangDetect`.
struct StaticLangDetector: LangDetecting {
    func detect(_ text: String) -> String {
        LangDetect.detect(text)
    }
}

// MARK: - Errors

enum SynthesisError: Error {
    case noProvider
    case missingURL
    case missingText
}

// MARK: - Observable state (MainActor, drives UI updates)

/// Lightweight observable wrapper that tracks synthesis queue depth
/// so SwiftUI views can reactively display "Synthesizing N of M".
@MainActor
@Observable
final class LibrarySynthesisState {
    /// Number of items queued + in-flight at this moment.
    private(set) var depth: Int = 0

    fileprivate func update(depth: Int) {
        self.depth = depth
    }
}

// MARK: - LibrarySynthesizer

actor LibrarySynthesizer {

    // MARK: - Dependencies

    private let store: LibraryStore
    private let extractor: any ArticleExtracting
    private let currentProviderProvider: (@Sendable () async -> (any TTSProvider)?)?
    private let durationProbe: any AudioDurationProbing
    private let langDetect: any LangDetecting
    private let audioDirectoryURL: URL

    // MARK: - Optional publisher (Drive)

    private var publisher: (any LibraryPublishing)?

    // MARK: - State

    private var queue: [UUID] = []
    private var inFlight: UUID?
    private var processor: Task<Void, Never>?
    private var cancelledIDs: Set<UUID> = []

    // MARK: - Observable state bridge

    private let synthesisState: LibrarySynthesisState

    // MARK: - Init

    init(
        store: LibraryStore,
        extractor: any ArticleExtracting,
        currentProviderProvider: (@Sendable () async -> (any TTSProvider)?)?,
        durationProbe: any AudioDurationProbing,
        langDetect: any LangDetecting,
        audioDirectoryURL: URL,
        synthesisState: LibrarySynthesisState
    ) {
        self.store = store
        self.extractor = extractor
        self.currentProviderProvider = currentProviderProvider
        self.durationProbe = durationProbe
        self.langDetect = langDetect
        self.audioDirectoryURL = audioDirectoryURL
        self.synthesisState = synthesisState
    }

    // MARK: - Public API

    /// Sets the Drive publisher. Called from AppDelegate after Drive is configured.
    func setPublisher(_ publisher: any LibraryPublishing) {
        self.publisher = publisher
    }

    /// Appends `itemID` to the queue and starts the processor if idle.
    func enqueue(itemID: UUID) {
        guard !queue.contains(itemID), inFlight != itemID else { return }
        queue.append(itemID)
        updateDepth()
        kickProcessor()
    }

    /// Snapshot `store.items` on the main actor and enqueue every `.pending` or `.failed` item.
    func enqueuePending() async {
        let items = await MainActor.run { store.items }
        for item in items {
            switch item.status {
            case .pending, .failed:
                enqueue(itemID: item.id)
            default:
                break
            }
        }
    }

    /// Removes `itemID` from the queue. If `itemID` is currently in-flight the processing
    /// loop checks for cancellation at each boundary and aborts.
    func cancel(itemID: UUID) {
        queue.removeAll { $0 == itemID }
        cancelledIDs.insert(itemID)
        updateDepth()
    }

    /// Returns the total number of pending + in-flight items.
    func currentDepth() -> Int {
        queue.count + (inFlight == nil ? 0 : 1)
    }

    // MARK: - Private: processor loop

    private func kickProcessor() {
        guard processor == nil else { return }
        processor = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    private func runLoop() async {
        while let next = popNext() {
            inFlight = next
            updateDepth()
            defer {
                inFlight = nil
                updateDepth()
            }

            guard let item = await loadItem(next) else { continue }

            if cancelledIDs.contains(next) {
                cancelledIDs.remove(next)
                continue
            }

            do {
                try await process(item)
            } catch {
                AppLogger.app.error("LibrarySynthesizer: item \(next.uuidString, privacy: .public) failed: \(error, privacy: .public)")
                await fail(itemID: next, reason: String(describing: error))
            }

            cancelledIDs.remove(next)
        }
        processor = nil
    }

    private func popNext() -> UUID? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    // MARK: - Private: item loading

    private func loadItem(_ id: UUID) async -> LibraryItem? {
        await MainActor.run { store.items.first { $0.id == id } }
    }

    // MARK: - Private: processing

    private func process(_ item: LibraryItem) async throws {
        let id = item.id
        var text: String
        var language: String

        // 1. Extraction phase
        switch item.sourceKind {
        case .url:
            guard let urlString = item.sourceURL, !urlString.isEmpty else {
                throw SynthesisError.missingURL
            }
            await updateStatus(id: id, status: .extracting)

            if checkCancelled(id) { throw CancellationError() }

            let article = try await extractor.extract(url: urlString)
            text = article.text
            language = article.language ?? "en"

            // Update title if previously nil.
            if let title = article.title, !title.isEmpty {
                await MainActor.run {
                    store.update(id: id) { item in
                        if item.title == nil || item.title?.isEmpty == true {
                            item.title = title
                        }
                    }
                }
            }

        case .text:
            guard let rawText = item.rawText, !rawText.isEmpty else {
                throw SynthesisError.missingText
            }
            text = rawText
            language = langDetect.detect(text)
        }

        if checkCancelled(id) { throw CancellationError() }

        // 2. Synthesizing phase
        await updateStatus(id: id, status: .synthesizing(progress: 0))

        let chunks = Chunker.chunk(text)

        guard let provider = await currentProviderProvider?() else {
            throw SynthesisError.noProvider
        }

        if checkCancelled(id) { throw CancellationError() }

        var collected: [Data] = []
        let totalChunks = max(chunks.count, 1)

        for try await chunkData in provider.synthesizeChunks(chunks, language: language) {
            if checkCancelled(id) { throw CancellationError() }
            if Task.isCancelled { throw CancellationError() }

            collected.append(chunkData)
            let progress = Double(collected.count) / Double(totalChunks)
            await updateStatus(id: id, status: .synthesizing(progress: progress))
        }

        if checkCancelled(id) { throw CancellationError() }

        // 3. Write MP3
        let filename = "\(id.uuidString).mp3"
        let outputURL = audioDirectoryURL.appendingPathComponent(filename)
        try MP3Concatenator.write(collected, to: outputURL)

        // 4. Probe duration
        let duration = try await durationProbe.duration(of: outputURL)

        // 5. Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let byteSize = (attrs[.size] as? Int64) ?? Int64(attrs[.size] as? Int ?? 0)

        // 6. Finalize item
        await MainActor.run {
            store.update(id: id) { item in
                item.status = .ready
                item.audioFilename = filename
                item.durationSeconds = duration
                item.byteSize = byteSize
                item.lastError = nil
            }
        }
        AppLogger.app.info("LibrarySynthesizer: item \(id.uuidString, privacy: .public) ready, dur=\(duration, privacy: .public)s size=\(byteSize, privacy: .public)B")

        // 7. Publish to Drive if configured.
        if let pub = publisher, DriveConfig.load()?.hasFolder == true {
            do {
                try await pub.publish(itemID: id)
            } catch PublisherError.notConnected {
                // Drive not configured yet; silently skip.
            } catch {
                AppLogger.app.error("LibrarySynthesizer: Drive publish failed for \(id.uuidString, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Private: helpers

    private func checkCancelled(_ id: UUID) -> Bool {
        cancelledIDs.contains(id)
    }

    private func updateStatus(id: UUID, status: LibraryItemStatus) async {
        await MainActor.run {
            store.update(id: id) { item in
                item.status = status
            }
        }
    }

    private func fail(itemID: UUID, reason: String) async {
        await MainActor.run {
            store.update(id: itemID) { item in
                item.status = .failed(reason: reason)
                item.lastError = reason
            }
        }
    }

    private func updateDepth() {
        let depth = currentDepth()
        let state = synthesisState
        Task { @MainActor in
            state.update(depth: depth)
        }
    }
}
