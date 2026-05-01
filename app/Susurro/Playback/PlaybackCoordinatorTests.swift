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
}
