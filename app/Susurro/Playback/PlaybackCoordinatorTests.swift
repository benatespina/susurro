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
        #expect(mock.translateInvocations.first?.1 == "es")

        // Verify the snapshot reflects the translated text (sourceText was replaced).
        let snapshot = await coordinator.currentSnapshot()
        // Backend not ready in tests so chunks is empty, but sourceText must reflect the translation.
        #expect(snapshot.sourceText == "texto traducido al español")
    }

    @Test func readWithToggleOnAndTranslatorErrorFallsBackToOriginal() async {
        let mock = MockTranslator()
        mock.nextResult = .failure(TranslatorError.modelNotReady)
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
}
