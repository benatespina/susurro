import Testing
@testable import Susurro

struct PlaybackCoordinatorTests {
    @Test func stopIsIdempotent() async {
        let coordinator = PlaybackCoordinator()

        await coordinator.stop()
        await coordinator.stop()
    }

    @Test func readThenStopClearsState() async {
        let coordinator = PlaybackCoordinator()

        // Registry not warmed up — tts will fail gracefully; we verify no crash.
        _ = await coordinator.read(text: "hello world")
        await coordinator.stop()
    }

    @Test func playingStatesEmitsFalseAfterStop() async {
        let coordinator = PlaybackCoordinator()

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

    @Test func readWhenNotReadyDoesNotCrash() async {
        let coordinator = PlaybackCoordinator()

        // Registry not warmed up — executeRead should bail at the health check.
        let task = Task { _ = await coordinator.read(text: "test text") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
    }
}
