import Foundation

/// A TTS synthesizer capable of warming up and synthesizing speech from text.
///
/// Renamed from the plan's `TTSProvider` to avoid collision with the `TTSProvider`
/// enum in `TTSSettings.swift` which represents the provider selection (edge vs azure).
///
/// `synthesizeChunked(text:language:)` SHOULD be implemented as
/// `synthesizeChunks(Chunker.chunk(text), language:)`.
/// A default implementation is not provided because `protocol: Actor` does not
/// compose cleanly with default implementations — implementors supply this themselves.
// TODO(Phase 5): rename `TTSSynthesizer` → `TTSProvider` when the existing
// `enum TTSProvider` in `app/Susurro/TTS/TTSSettings.swift` is renamed to
// `TTSProviderKind`. Two-step rename keeps Phase 3 + 4 from touching
// settings code.
protocol TTSSynthesizer: Actor {
    func warmup() async throws
    func synthesize(text: String, language: String) async throws -> Data
    nonisolated func synthesizeStream(text: String, language: String) -> AsyncThrowingStream<Data, Error>
    nonisolated func synthesizeChunks(_ chunks: [String], language: String) -> AsyncThrowingStream<Data, Error>
    nonisolated func synthesizeChunked(text: String, language: String) -> AsyncThrowingStream<Data, Error>
    func synthesizePreview(ssml: String, language: String) async throws -> Data
}
