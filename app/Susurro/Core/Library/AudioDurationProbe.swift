import AVFoundation
import Foundation

// MARK: - Protocol

/// A type that can measure the duration (in seconds) of an audio file at a given URL.
protocol AudioDurationProbing: Sendable {
    func duration(of url: URL) async throws -> Double
}

// MARK: - AVFoundation implementation

/// Probes audio duration using `AVURLAsset`.
struct AVAudioDurationProbe: AudioDurationProbing {
    func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let cmTime = try await asset.load(.duration)
        return CMTimeGetSeconds(cmTime)
    }
}
