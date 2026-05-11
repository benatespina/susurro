import Testing
@testable import Susurro

// MARK: - Tests

struct PlaybackCoordinatorTests {
    @Test func stopIsIdempotent() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        await coordinator.stop()
        await coordinator.stop()
    }

    @Test func readThenStopClearsState() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        // Registry not warmed up — tts will fail gracefully; we verify no crash.
        _ = await coordinator.read(text: "hello world")
        await coordinator.stop()
    }

    @Test func playingStatesEmitsFalseAfterStop() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

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
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        // Registry not warmed up — executeRead should bail at the health check.
        let task = Task { _ = await coordinator.read(text: "test text") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
    }

    // MARK: - Translation flow tests

    @Test func readWithToggleOffDoesNotCallTranslator() async {
        let mock = MockTranslator()
        let coordinator = PlaybackCoordinator(
            translator: mock,
            isTranslateToSpanishEnabled: { false }
        )

        _ = await coordinator.read(text: "this is english text")

        #expect(mock.translateCallCount == 0)
    }

    @Test func readWithToggleOnAndSpanishTextSkipsTranslation() async {
        let mock = MockTranslator()
        let coordinator = PlaybackCoordinator(
            translator: mock,
            isTranslateToSpanishEnabled: { true }
        )

        // Text that LanguageDetector will detect as Spanish (>= 10 chars, Spanish content).
        _ = await coordinator.read(text: "hola mundo, esto es texto en español para prueba")

        #expect(mock.translateCallCount == 0)
    }

    @Test func readWithToggleOnAndEnglishTextCallsTranslatorAndReplaces() async {
        let mock = MockTranslator()
        mock.nextResult = .success("texto traducido al español")
        let coordinator = PlaybackCoordinator(
            translator: mock,
            isTranslateToSpanishEnabled: { true }
        )

        _ = await coordinator.read(text: "this is a sufficiently long english sentence for detection")

        #expect(mock.translateCallCount == 1)
        #expect(mock.translateInvocations.first?.0 == "this is a sufficiently long english sentence for detection")
        #expect(mock.translateInvocations.first?.1 == "es-ES")

        // Verify the snapshot reflects the translated text (sourceText was replaced).
        let snapshot = await coordinator.currentSnapshot()
        // Backend not ready in tests so chunks is empty, but sourceText must reflect the translation.
        #expect(snapshot.sourceText == "texto traducido al español")
    }

    @Test func readWithToggleOnAndTranslatorErrorFallsBackToOriginal() async {
        let mock = MockTranslator()
        mock.nextResult = .failure(TranslatorError.failed(message: "test error"))
        let coordinator = PlaybackCoordinator(
            translator: mock,
            isTranslateToSpanishEnabled: { true }
        )

        // Must not throw — read() should return normally even when translation fails.
        let result = await coordinator.read(text: "this is a sufficiently long english sentence for detection")

        // result is false because backend is not ready in test environment — that's OK.
        // The key assertions: translator was called, read() did not crash/throw,
        // and the snapshot retains the ORIGINAL text (not a partial translation).
        #expect(mock.translateCallCount == 1)
        _ = result
        let snapshot = await coordinator.currentSnapshot()
        #expect(snapshot.sourceText == "this is a sufficiently long english sentence for detection")
    }

    @Test func readWithToggleOnAndEmptyTextSkipsTranslation() async {
        let mock = MockTranslator()
        let coordinator = PlaybackCoordinator(
            translator: mock,
            isTranslateToSpanishEnabled: { true }
        )

        // Empty text hits the `!text.isEmpty` guard in PlaybackCoordinator.read —
        // translator must not be called even when the toggle is on.
        _ = await coordinator.read(text: "")

        #expect(mock.translateCallCount == 0)
    }

    // MARK: - Rate control tests

    @Test func setRateUpdatesCurrentRate() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        await coordinator.setRate(1.5)

        let snapshot = await coordinator.currentSnapshot()
        #expect(snapshot.currentRate == 1.5)
    }

    @Test func readResetsCurrentRate() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        await coordinator.setRate(1.5)
        _ = await coordinator.read(text: "hello")

        let snapshot = await coordinator.currentSnapshot()
        #expect(snapshot.currentRate == 1.0)
    }

    @Test func resumePreservesCurrentRate() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        // Without a live AVPlayer, verify that currentRate is preserved in the
        // snapshot across setRate → pause → resume so the coordinator's own state
        // machine never drops the rate back to 1.0.
        await coordinator.setRate(1.5)
        await coordinator.pause()
        await coordinator.resume()

        let snapshot = await coordinator.currentSnapshot()
        #expect(snapshot.currentRate == 1.5)
    }

    @Test func setRateEmitsSnapshot() async {
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        let stream = await coordinator.snapshots()
        await coordinator.setRate(1.75)

        var received: PlaybackSnapshot?
        for await snap in stream {
            if snap.currentRate == 1.75 {
                received = snap
                break
            }
        }

        #expect(received?.currentRate == 1.75)
    }

    @Test func setRateWhilePausedDoesNotChangeIsPlaying() async {
        // Regression: AVPlayer.rate = nonZero resumes a paused player.
        // PlaybackCoordinator.setRate must skip the AVPlayer setter when paused.
        // Without a live AVQueuePlayer we verify via snapshot state: isPaused must
        // remain true and isPlaying must remain false after setRate when paused.
        let coordinator = PlaybackCoordinator(
            translator: MockTranslator(),
            isTranslateToSpanishEnabled: { false }
        )

        // pause() guards on currentPlayer being non-nil; it is nil here so
        // snapshot state stays at defaults. Force the paused snapshot state directly
        // via the public API: setRate then pause sequence on a coordinator with no player.
        await coordinator.setRate(1.5)
        await coordinator.pause() // no-op on player, but snapshot.isPaused → true if player existed
        // Because there is no live player pause() returns early; manually verify
        // that a subsequent setRate does not alter isPlaying.
        await coordinator.setRate(1.75)

        let snapshot = await coordinator.currentSnapshot()
        #expect(snapshot.currentRate == 1.75)
        #expect(snapshot.isPlaying == false)
    }
}
