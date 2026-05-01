import AVFoundation
import Foundation
import os

struct PlaybackSnapshot: Sendable, Equatable {
    var chunks: [String]
    var currentChunkIndex: Int
    var isPlaying: Bool
    var isPaused: Bool
    var title: String?

    static let empty = PlaybackSnapshot(chunks: [], currentChunkIndex: 0, isPlaying: false, isPaused: false, title: nil)
}

actor PlaybackCoordinator {
    private let backend: BackendProcess
    private var currentTask: Task<Void, Never>?
    private var currentPlayer: AVQueuePlayer?
    private var currentTempDir: URL?
    private var stateContinuations: [AsyncStream<Bool>.Continuation] = []
    private var snapshotContinuations: [AsyncStream<PlaybackSnapshot>.Continuation] = []

    private var sourceText: String = ""
    private var chunks: [String] = []
    private var snapshot: PlaybackSnapshot = .empty
    private var currentTitle: String?

    private var streamStartChunk: Int = 0
    private var itemsPlayedInStream: Int = 0
    private var observedItems: Set<ObjectIdentifier> = []
    private var observerTask: Task<Void, Never>?

    init(backend: BackendProcess) {
        self.backend = backend
    }

    func read(text: String) async {
        await read(text: text, title: nil)
    }

    func read(text: String, title: String?) async {
        await stop(preserveTranscript: false)
        currentTitle = title
        sourceText = text

        guard case .ready(let client) = await backend.state else {
            AppLogger.playback.error("backend not ready, cannot read")
            return
        }
        do {
            let result = try await client.fetchChunks(text: text, language: nil)
            chunks = result
        } catch {
            AppLogger.playback.error("chunks fetch failed: \(error.localizedDescription, privacy: .public)")
            chunks = []
        }
        snapshot = PlaybackSnapshot(
            chunks: chunks, currentChunkIndex: 0, isPlaying: false, isPaused: false, title: currentTitle
        )
        emitSnapshot()
        persistSnapshot()

        startStream(fromChunk: 0)
    }

    /// Restore a previously persisted session into memory without auto-playing.
    /// Once restored, callers can show the transcript window or trigger
    /// `seek(toChunk:)` to resume audio from where the user left off.
    func restorePersistedSession() async {
        guard chunks.isEmpty else { return }
        guard let session = SessionStore.load() else { return }
        sourceText = session.text
        chunks = session.chunks
        snapshot = PlaybackSnapshot(
            chunks: session.chunks,
            currentChunkIndex: min(session.currentChunkIndex, max(0, session.chunks.count - 1)),
            isPlaying: false,
            isPaused: false,
            title: nil
        )
        emitSnapshot()
    }

    func hasRestorableSession() -> Bool {
        !chunks.isEmpty && !sourceText.isEmpty
    }

    func seek(toChunk index: Int) async {
        guard !chunks.isEmpty, index >= 0, index < chunks.count else { return }
        await stop(preserveTranscript: true)
        snapshot.currentChunkIndex = index
        snapshot.isPlaying = false
        snapshot.isPaused = false
        emitSnapshot()
        persistSnapshot()
        startStream(fromChunk: index)
    }

    func pause() async {
        guard let player = currentPlayer else { return }
        await MainActor.run { player.pause() }
        snapshot.isPaused = true
        snapshot.isPlaying = false
        emitSnapshot()
        persistSnapshot()
        emitPlaying(false)
    }

    func resume() async {
        guard let player = currentPlayer else { return }
        await MainActor.run { player.play() }
        snapshot.isPaused = false
        snapshot.isPlaying = true
        emitSnapshot()
        emitPlaying(true)
    }

    func stop() async {
        await stop(preserveTranscript: false)
    }

    private func stop(preserveTranscript: Bool) async {
        currentTask?.cancel()
        currentTask = nil
        observerTask?.cancel()
        observerTask = nil
        observedItems.removeAll()

        if let player = currentPlayer {
            await MainActor.run {
                player.pause()
                player.removeAllItems()
            }
        }
        currentPlayer = nil

        if let dir = currentTempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        currentTempDir = nil

        if case .ready(let client) = await backend.state {
            try? await client.stop()
        }

        if !preserveTranscript {
            sourceText = ""
            chunks = []
            currentTitle = nil
            snapshot = .empty
            emitSnapshot()
            SessionStore.clear()
        } else {
            snapshot.isPlaying = false
            snapshot.isPaused = false
            emitSnapshot()
            persistSnapshot()
        }
        emitPlaying(false)
    }

    func playingStates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            stateContinuations.append(continuation)
            continuation.onTermination = { _ in }
        }
    }

    func snapshots() -> AsyncStream<PlaybackSnapshot> {
        AsyncStream { continuation in
            snapshotContinuations.append(continuation)
            continuation.yield(snapshot)
            continuation.onTermination = { _ in }
        }
    }

    func currentSnapshot() -> PlaybackSnapshot { snapshot }

    private func startStream(fromChunk index: Int) {
        streamStartChunk = index
        itemsPlayedInStream = 0
        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeStream(startChunk: index)
        }
        currentTask = task
    }

    private func executeStream(startChunk: Int) async {
        guard case .ready(let client) = await backend.state else {
            AppLogger.playback.error("backend not ready, cannot stream")
            return
        }

        let request: URLRequest
        do {
            request = try client.streamingTTSRequest(
                text: sourceText, language: nil, startChunk: startChunk
            )
        } catch {
            AppLogger.playback.error("tts stream request build failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        } catch is CancellationError {
            return
        } catch {
            AppLogger.playback.error("tts stream open failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            AppLogger.playback.error("tts stream http=\(status, privacy: .public)")
            return
        }

        let player = await MainActor.run { AVQueuePlayer() }
        currentPlayer = player

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("susurro-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        currentTempDir = tempDir

        startObservingItemEnds()

        var iter = asyncBytes.makeAsyncIterator()
        var fileIndex = 0
        var startedPlaying = false

        readLoop: while !Task.isCancelled {
            guard let lenBytes = await readExact(4, from: &iter) else { break }
            let length = (UInt32(lenBytes[0]) << 24)
                | (UInt32(lenBytes[1]) << 16)
                | (UInt32(lenBytes[2]) << 8)
                | UInt32(lenBytes[3])
            if length == 0 { break }
            guard let chunk = await readExact(Int(length), from: &iter) else { break }

            let url = tempDir.appendingPathComponent("\(fileIndex).mp3")
            fileIndex += 1
            do {
                try chunk.write(to: url)
            } catch {
                AppLogger.playback.error("tts chunk write failed: \(error.localizedDescription, privacy: .public)")
                continue readLoop
            }

            let item = AVPlayerItem(url: url)
            observedItems.insert(ObjectIdentifier(item))
            await MainActor.run {
                player.insert(item, after: nil)
                if !startedPlaying {
                    player.play()
                }
            }
            if !startedPlaying {
                startedPlaying = true
                snapshot.isPlaying = true
                snapshot.isPaused = false
                snapshot.currentChunkIndex = startChunk
                emitSnapshot()
                emitPlaying(true)
            }
        }

        if Task.isCancelled {
            return
        }

        while !Task.isCancelled {
            let remaining = await MainActor.run { player.items().count }
            if remaining == 0 { break }
            try? await Task.sleep(for: .milliseconds(200))
        }

        currentPlayer = nil
        try? FileManager.default.removeItem(at: tempDir)
        currentTempDir = nil
        observerTask?.cancel()
        observerTask = nil
        observedItems.removeAll()
        snapshot.isPlaying = false
        snapshot.isPaused = false
        emitSnapshot()
        emitPlaying(false)
        AppLogger.playback.info("playback finished, chunks=\(fileIndex, privacy: .public)")
    }

    private func startObservingItemEnds() {
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            let stream = NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime
            )
            for await notif in stream {
                if Task.isCancelled { return }
                guard let item = notif.object as? AVPlayerItem else { continue }
                await self?.handleItemEnd(itemID: ObjectIdentifier(item))
            }
        }
    }

    private func handleItemEnd(itemID: ObjectIdentifier) async {
        guard observedItems.contains(itemID) else { return }
        observedItems.remove(itemID)
        itemsPlayedInStream += 1
        let nextIndex = streamStartChunk + itemsPlayedInStream
        if nextIndex < chunks.count {
            snapshot.currentChunkIndex = nextIndex
            emitSnapshot()
            persistSnapshot()
        }
    }

    private func persistSnapshot() {
        guard !chunks.isEmpty, !sourceText.isEmpty else { return }
        let session = PersistedSession(
            text: sourceText,
            chunks: chunks,
            currentChunkIndex: snapshot.currentChunkIndex,
            savedAt: Date()
        )
        SessionStore.save(session)
    }

    private func readExact(
        _ count: Int,
        from iterator: inout URLSession.AsyncBytes.AsyncIterator
    ) async -> Data? {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            do {
                guard let byte = try await iterator.next() else { return nil }
                data.append(byte)
            } catch {
                return nil
            }
        }
        return data
    }

    private func emitPlaying(_ playing: Bool) {
        for continuation in stateContinuations { continuation.yield(playing) }
    }

    private func emitSnapshot() {
        for continuation in snapshotContinuations { continuation.yield(snapshot) }
    }
}
