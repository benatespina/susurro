import Foundation
@testable import Susurro

// MARK: - Shared test double

/// Consolidated mock for `TranslatorProviding`. Covers both simple result/error
/// assertions (used in `TranslatorTests`) and call-tracking assertions (used in
/// `PlaybackCoordinatorTests`).
final class MockTranslator: TranslatorProviding, @unchecked Sendable {
    // MARK: Result configuration

    /// Convenience setter kept for `TranslatorTests` compatibility.
    var result: String {
        get {
            if case .success(let s) = nextResult { return s }
            return ""
        }
        set { nextResult = .success(newValue) }
    }

    /// Convenience setter kept for `TranslatorTests` compatibility.
    var errorToThrow: Error? {
        didSet {
            if let error = errorToThrow {
                nextResult = .failure(error)
            } else {
                nextResult = .success("MOCK_TRANSLATED")
            }
        }
    }

    /// Primary result configuration used by `PlaybackCoordinatorTests`.
    var nextResult: Result<String, Error> = .success("MOCK_TRANSLATED")

    // MARK: Call tracking

    private(set) var translateCallCount = 0
    private(set) var translateInvocations: [(text: String, target: String)] = []

    /// Most-recent text argument — kept for `TranslatorTests` compatibility.
    var lastText: String? { translateInvocations.last?.text }

    /// Most-recent target-language argument — kept for `TranslatorTests` compatibility.
    var lastTarget: String? { translateInvocations.last?.target }

    // MARK: TranslatorProviding

    func translate(_ text: String, to targetLanguage: String) async throws -> String {
        translateCallCount += 1
        translateInvocations.append((text: text, target: targetLanguage))
        return try nextResult.get()
    }
}
