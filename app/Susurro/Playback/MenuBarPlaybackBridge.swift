// Susurro — Observable bridge mirroring playback snapshot state for the menu bar

import Foundation
import Observation

@MainActor @Observable
final class MenuBarPlaybackBridge {
    // Populated by Phase E once content extraction threads title into PlaybackSnapshot.
    var title: String?
    var chunkCount: Int = 0
    var currentChunk: Int = 0
    var isPaused: Bool = false

    // Stored as a class-level box so deinit (nonisolated) can cancel it.
    private let taskBox = TaskBox()

    init(coordinator: PlaybackCoordinator) {
        let box = taskBox
        box.task = Task { [weak self] in
            let stream = await coordinator.snapshots()
            for await snap in stream {
                guard let self else { return }
                self.chunkCount = snap.chunks.count
                self.currentChunk = snap.currentChunkIndex
                self.isPaused = snap.isPaused
            }
        }
    }

    func cancel() {
        taskBox.task?.cancel()
        taskBox.task = nil
    }
}

private final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
}
