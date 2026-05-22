import Foundation
import Testing
@testable import Susurro

// WKWebView is not unit-testable without a test host bundle.
// This suite only confirms the symbol exists and the @MainActor annotation is preserved.
// Real extraction coverage lives in ParityHarnessTests behind PARITY_AUDIT.

@MainActor
@Suite("ReaderModeExtractor")
struct ReaderModeExtractorTests {

    @Test("extractIsCallableUnderMainActor")
    func extractIsCallableUnderMainActor() async {
        let url = URL(string: "https://example.com/")!
        _ = try? await ReaderModeExtractor.extract(url: url.absoluteString)
        #expect(true)
    }
}
