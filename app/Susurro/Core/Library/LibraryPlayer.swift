import AVFoundation
import Foundation
import Observation
import os

@MainActor @Observable
final class LibraryPlayer {
    var nowPlayingID: UUID?
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Float = 1.0

    // nonisolated(unsafe) is intentional: player and observer are created/torn down
    // on the main actor, but Swift 6 strict concurrency cannot verify deinit isolation.
    nonisolated(unsafe) private var player: AVPlayer?
    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var itemEndObserver: NSObjectProtocol?

    func play(item: LibraryItem, audioURL: URL) {
        stop()

        let avItem = AVPlayerItem(url: audioURL)
        let avPlayer = AVPlayer(playerItem: avItem)
        avPlayer.rate = playbackRate
        self.player = avPlayer

        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds.isNaN ? 0 : time.seconds
            if let d = avPlayer.currentItem?.duration.seconds, !d.isNaN, !d.isInfinite {
                self.duration = d
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: avItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.currentTime = 0
        }

        nowPlayingID = item.id
        isPlaying = true
        avPlayer.play()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        if nowPlayingID != nil {
            isPlaying = true
        }
    }

    func stop() {
        player?.pause()
        removeObservers()
        player = nil
        nowPlayingID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    // MARK: - Private

    private func removeObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
            itemEndObserver = nil
        }
    }

    deinit {
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
        }
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
