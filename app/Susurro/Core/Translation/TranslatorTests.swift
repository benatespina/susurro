import Foundation
import Testing
@testable import Susurro

// MARK: - Mock

/// Test double that fulfils `TranslatorProviding` without touching the real
/// Translation framework. Configure `result` / `errorToThrow` per test.
final class MockTranslator: TranslatorProviding, @unchecked Sendable {
    var result: String = ""
    var errorToThrow: Error?
    private(set) var lastText: String?
    private(set) var lastTarget: String?

    func translate(_ text: String, to targetLanguage: String) async throws -> String {
        lastText = text
        lastTarget = targetLanguage
        if let error = errorToThrow { throw error }
        return result
    }
}

// MARK: - Unit tests (mock-based, run in CI)

@Suite struct TranslatorTests {

    // MARK: Empty text short-circuit

    /// Verifies the real `Translator` short-circuits before touching the Translation
    /// framework — this does NOT require a downloaded model or network access.
    @Test func emptyTextReturnsEmptyFromTranslator() async throws {
        let output = try await Translator.shared.translate("", to: "es")
        #expect(output == "")
    }

    /// Confirms the mock honours whatever contract the caller sets; downstream code
    /// relying on `TranslatorProviding` can supply a mock that short-circuits empty
    /// text too if desired.
    @Test func mockTranslatorPassesThroughResult() async throws {
        let mock = MockTranslator()
        mock.result = "Hola"
        let output = try await mock.translate("Hi", to: "es")
        #expect(output == "Hola")
        #expect(mock.lastText == "Hi")
    }

    // MARK: Successful translation (mock)

    @Test func successfulTranslationReturnsMockResult() async throws {
        let mock = MockTranslator()
        mock.result = "Hola mundo"
        let output = try await mock.translate("Hello world", to: "es")
        #expect(output == "Hola mundo")
        #expect(mock.lastText == "Hello world")
        #expect(mock.lastTarget == "es")
    }

    // MARK: Error path via mock

    @Test func failedTranslationThrowsExpectedError() async throws {
        let mock = MockTranslator()
        mock.errorToThrow = TranslatorError.failed(message: "network gone")
        await #expect(throws: TranslatorError.self) {
            _ = try await mock.translate("test", to: "es")
        }
    }

    @Test func modelNotReadyErrorPropagatesToCaller() async throws {
        let mock = MockTranslator()
        mock.errorToThrow = TranslatorError.modelNotReady
        await #expect(throws: TranslatorError.modelNotReady) {
            _ = try await mock.translate("any text", to: "es")
        }
    }

    // MARK: TranslatorError Sendable / Equatable checks

    @Test func translatorErrorEquatable() {
        #expect(TranslatorError.modelNotReady == .modelNotReady)
        #expect(TranslatorError.failed(message: "x") == .failed(message: "x"))
        #expect(TranslatorError.failed(message: "x") != .failed(message: "y"))
    }
}

// MARK: - Smoke tests (real Translation framework — only when env var set)

/// These tests call the real `Translator` and therefore require:
/// 1. macOS 26+
/// 2. Internet access (first run) or a pre-downloaded Spanish language model
/// 3. `SUSURRO_TRANSLATION_SMOKE=1` in the process environment
///
/// They are intentionally excluded from CI. Run locally with:
///   SUSURRO_TRANSLATION_SMOKE=1 xcodebuild test …
@Suite struct TranslatorSmokeTests {

    private var smokeEnabled: Bool {
        ProcessInfo.processInfo.environment["SUSURRO_TRANSLATION_SMOKE"] == "1"
    }

    @Test func smokeEnToEs() async throws {
        guard smokeEnabled else { return }
        let result = try await Translator.shared.translate("Hello, world", to: "es")
        // The exact translation may vary; just verify non-empty and not identical to input.
        #expect(!result.isEmpty)
        #expect(result != "Hello, world")
    }

    @Test func smokeEmptyTextNoError() async throws {
        guard smokeEnabled else { return }
        let result = try await Translator.shared.translate("", to: "es")
        #expect(result == "")
    }

    @Test func smokeSpanishInputRoundtrips() async throws {
        guard smokeEnabled else { return }
        // Already-Spanish text should come back unchanged or near-unchanged.
        let input = "Hola, ¿cómo estás?"
        let result = try await Translator.shared.translate(input, to: "es")
        #expect(!result.isEmpty)
    }
}
