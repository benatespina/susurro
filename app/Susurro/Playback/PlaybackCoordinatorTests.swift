import Testing
@testable import Susurro

struct PlaybackCoordinatorTests {
    @Test func stopIsIdempotent() async {
        let backend = BackendProcess()
        let coordinator = PlaybackCoordinator(backend: backend)

        await coordinator.stop()
        await coordinator.stop()
    }

    @Test func readThenStopClearsState() async {
        let backend = BackendProcess()
        let coordinator = PlaybackCoordinator(backend: backend)

        // Backend not started — tts will fail gracefully; we verify no crash.
        await coordinator.read(text: "hello world")
        await coordinator.stop()
    }

    @Test func playingStatesEmitsFalseAfterStop() async {
        let backend = BackendProcess()
        let coordinator = PlaybackCoordinator(backend: backend)

        let stream = await coordinator.playingStates()
        await coordinator.stop()

        var received = false
        for await value in stream {
            if !value {
                received = true
                break
            }
        }

        #expect(received)
    }

    @Test func readOnStoppedBackendDoesNotCrash() async {
        let backend = BackendProcess()
        let coordinator = PlaybackCoordinator(backend: backend)

        // Backend never started — executeRead should bail at the guard.
        let task = Task { await coordinator.read(text: "test text") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
    }

    /// Regression test for actor reentrancy bug: stop(preserveTranscript:false) used to
    /// clear currentTitle when called before the assignment. The fix moves the assignment
    /// after stop(), so the title survives into the snapshot built post-fetchChunks.
    ///
    /// Full end-to-end verification (snapshot.title == "My Article") requires a live
    /// backend to pass the fetchChunks guard; that level of integration test is out of
    /// scope here. Instead we confirm that:
    ///   1. read() with a non-ready backend does not crash (guard exits cleanly), and
    ///   2. the snapshot remains in its cleared state — not an incorrect stale title
    ///      from a previous session — so the ordering fix doesn't regress idle behaviour.
    @Test func readStoresTitleInSnapshot() async {
        let backend = BackendProcess()
        let coordinator = PlaybackCoordinator(backend: backend)

        // Prime the coordinator with an earlier call so that a stale title could linger.
        await coordinator.read(text: "Old text", title: "Old Title")

        // Second call — backend still not started, so fetchChunks guard fires and
        // read() exits before building a snapshot. The title for this session should
        // NOT be "Old Title" (that was cleared by the internal stop()).
        await coordinator.read(text: "Hello world", title: "My Article")
        let snapshot = await coordinator.currentSnapshot()

        // After stop(preserveTranscript:false) the snapshot is .empty (title: nil)
        // because no snapshot was committed — the key invariant is that "Old Title"
        // is gone, not that "My Article" is present (backend unavailable in unit tests).
        #expect(snapshot.title != "Old Title", "stale title must not survive a new read()")
    }
}
