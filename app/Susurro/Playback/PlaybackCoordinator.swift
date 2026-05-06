import AppKit
import AVFoundation
import Foundation
import os

struct PlaybackSnapshot: Sendable, Equatable {
    var sourceText: String
    var chunks: [String]
    var currentChunkIndex: Int
    var isPlaying: Bool
    var isPaused: Bool

    static let empty = PlaybackSnapshot(sourceText: "", chunks: [], currentChunkIndex: 0, isPlaying: false, isPaused: false)
}

actor PlaybackCoordinator {
    private let client: BackendClient
    private let translator: any TranslatorProviding
    private let isTranslateToSpanishEnabled: @Sendable () -> Bool
    private var currentTask: Task<Void, Never>?
    private var currentPlayer: AVQueuePlayer?
    private var currentTempDir: URL?
    private var stateContinuations: [AsyncStream<Bool>.Continuation] = []
    private var snapshotContinuations: [AsyncStream<PlaybackSnapshot>.Continuation] = []

    private var sourceText: String = ""
    private var sourceLanguage: String?
    private var chunks: [String] = []
    private var snapshot: PlaybackSnapshot = .empty

    private var streamStartChunk: Int = 0
    private var itemsPlayedInStream: Int = 0
    private var observedItems: Set<ObjectIdentifier> = []
    private var observerTask: Task<Void, Never>?

    init(
        client: BackendClient = .shared,
        translator: any TranslatorProviding,
        isTranslateToSpanishEnabled: @escaping @Sendable () -> Bool = { false }
    ) {
        self.client = client
        self.translator = translator
        self.isTranslateToSpanishEnabled = isTranslateToSpanishEnabled
    }

    func read(text: String) async -> Bool {
        await stop(preserveTranscript: false)
        var effectiveText = text
        var effectiveLang = LanguageDetector.detect(in: text)

        if isTranslateToSpanishEnabled() && effectiveLang != "es" && !text.isEmpty {
            do {
                effectiveText = try await translator.translate(text, to: "es-ES")
                effectiveLang = "es"
            } catch {
                AppLogger.playback.error("translation failed: \(error.localizedDescription, privacy: .public)")
                if case TranslatorError.modelNotReady = error {
                    await MainActor.run { Self.showModelNotReadyAlertIfNeeded(targetLanguage: "Spanish") }
                }
                // Fall back to original text and detected language.
            }
        }

        sourceText = effectiveText
        sourceLanguage = effectiveLang
        snapshot = PlaybackSnapshot(
            sourceText: effectiveText, chunks: [], currentChunkIndex: 0, isPlaying: false, isPaused: false
        )

        let health = await client.health()
        guard health == .ready else {
            AppLogger.playback.error("backend not ready, cannot read")
            return false
        }

        let result = await client.fetchChunks(text: effectiveText, language: sourceLanguage)
        chunks = result.chunks

        snapshot = PlaybackSnapshot(
            sourceText: effectiveText, chunks: chunks, currentChunkIndex: 0, isPlaying: false, isPaused: false
        )
        emitSnapshot()
        persistSnapshot()

        startStream(fromChunk: 0)
        return true
    }

    /// Restore a previously persisted session into memory without auto-playing.
    /// Once restored, callers can show the transcript window or trigger
    /// `seek(toChunk:)` to resume audio from where the user left off.
    func restorePersistedSession() async {
        guard chunks.isEmpty else { return }
        guard let session = SessionStore.load() else { return }
        sourceText = session.text
        sourceLanguage = LanguageDetector.detect(in: session.text)
        chunks = session.chunks
        snapshot = PlaybackSnapshot(
            sourceText: session.text,
            chunks: session.chunks,
            currentChunkIndex: min(session.currentChunkIndex, max(0, session.chunks.count - 1)),
            isPlaying: false,
            isPaused: false
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

        if !preserveTranscript {
            sourceText = ""
            chunks = []
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
        let health = await client.health()
        guard health == .ready else {
            AppLogger.playback.error("backend not ready, cannot stream")
            return
        }

        let player = await MainActor.run { AVQueuePlayer() }
        currentPlayer = player

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("susurro-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        currentTempDir = tempDir

        startObservingItemEnds()

        var fileIndex = 0
        var startedPlaying = false

        do {
            for try await mp3Chunk in client.streamingTTS(
                text: sourceText,
                language: sourceLanguage,
                startChunk: startChunk
            ) {
                if Task.isCancelled { break }

                let url = tempDir.appendingPathComponent("\(fileIndex).mp3")
                fileIndex += 1
                do {
                    try mp3Chunk.write(to: url)
                } catch {
                    AppLogger.playback.error("tts chunk write failed: \(error.localizedDescription, privacy: .public)")
                    continue
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
        } catch is CancellationError {
            return
        } catch {
            AppLogger.playback.error("tts stream failed: \(error.localizedDescription, privacy: .public)")
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

    private func emitPlaying(_ playing: Bool) {
        for continuation in stateContinuations { continuation.yield(playing) }
    }

    private func emitSnapshot() {
        for continuation in snapshotContinuations { continuation.yield(snapshot) }
    }

    // MARK: - Model-not-ready alert

    @MainActor
    private static var modelAlertShownThisSession = false

    @MainActor
    private static func showModelNotReadyAlertIfNeeded(targetLanguage: String) {
        guard !modelAlertShownThisSession else {
            AppLogger.playback.info("modelNotReady alert already shown this session — skipping")
            return
        }
        modelAlertShownThisSession = true

        AppLogger.playback.info("presenting modelNotReady alert for \(targetLanguage, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Spanish translation model not installed"
        alert.informativeText = """
            Susurro could not load the on-device \(targetLanguage) translation model.

            To install it:
            1. Open System Settings → General → Language & Region.
            2. Click Translation Languages.
            3. Add Spanish (or your target language) and wait for it to download.
            4. Try reading the text again.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if let panel = alert.window as? NSPanel {
            panel.level = .modalPanel
        } else {
            alert.window.level = .modalPanel
        }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: "x-apple.systempreferences:") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
