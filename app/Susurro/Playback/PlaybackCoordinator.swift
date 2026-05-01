import AVFoundation
import Foundation
import os

actor PlaybackCoordinator {
    private let backend: BackendProcess
    private var currentTask: Task<Void, Never>?
    private var currentPlayer: AVQueuePlayer?
    private var currentTempDir: URL?
    private var stateContinuations: [AsyncStream<Bool>.Continuation] = []

    init(backend: BackendProcess) {
        self.backend = backend
    }

    func read(text: String) async {
        await stop()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeRead(text: text)
        }
        currentTask = task
    }

    func stop() async {
        currentTask?.cancel()
        currentTask = nil

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

        emitPlaying(false)
    }

    func playingStates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            stateContinuations.append(continuation)
            continuation.onTermination = { _ in }
        }
    }

    private func executeRead(text: String) async {
        guard case .ready(let client) = await backend.state else {
            AppLogger.playback.error("backend not ready, cannot read")
            return
        }

        let request: URLRequest
        do {
            request = try client.streamingTTSRequest(text: text, language: nil)
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
            await MainActor.run {
                player.insert(item, after: nil)
                if !startedPlaying {
                    player.play()
                }
            }
            if !startedPlaying {
                startedPlaying = true
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
        emitPlaying(false)
        AppLogger.playback.info("playback finished, chunks=\(fileIndex, privacy: .public)")
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
}
