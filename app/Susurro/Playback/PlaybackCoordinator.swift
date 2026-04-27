import AVFAudio
import Foundation
import os

actor PlaybackCoordinator {
    private let backend: BackendProcess
    private var currentTask: Task<Void, Never>?
    private var currentPlayer: AVAudioPlayer?
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

        currentPlayer?.stop()
        currentPlayer = nil

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

        let data: Data
        do {
            data = try await client.tts(text: text, language: nil)
        } catch is CancellationError {
            return
        } catch {
            AppLogger.playback.error("tts fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if Task.isCancelled { return }

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            AppLogger.playback.error("audio player init failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        currentPlayer = player
        emitPlaying(true)

        let didFinish = await playUntilFinished(player: player)
        currentPlayer = nil
        emitPlaying(false)
        AppLogger.playback.info("playback finished cleanly: \(didFinish, privacy: .public)")
    }

    private func playUntilFinished(player: AVAudioPlayer) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let delegate = PlaybackFinishedDelegate { didFinish in
                continuation.resume(returning: didFinish)
            }
            player.delegate = delegate
            objc_setAssociatedObject(player, "PlaybackFinishedDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            player.prepareToPlay()
            player.play()
        }
    }

    private func emitPlaying(_ playing: Bool) {
        for continuation in stateContinuations { continuation.yield(playing) }
    }
}

private final class PlaybackFinishedDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: (Bool) -> Void

    init(onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish(flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish(false)
    }
}
