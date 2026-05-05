import Foundation

/// A TTS provider capable of warming up and synthesizing speech from text.
///
/// `synthesizeChunked(text:language:)` SHOULD be implemented as
/// `synthesizeChunks(Chunker.chunk(text), language:)`.
/// A default implementation is not provided because `protocol: Actor` does not
/// compose cleanly with default implementations — implementors supply this themselves.
protocol TTSProvider: Actor {
    func warmup() async throws
    func synthesize(text: String, language: String) async throws -> Data
    nonisolated func synthesizeStream(text: String, language: String) -> AsyncThrowingStream<Data, Error>
    nonisolated func synthesizeChunks(_ chunks: [String], language: String) -> AsyncThrowingStream<Data, Error>
    nonisolated func synthesizeChunked(text: String, language: String) -> AsyncThrowingStream<Data, Error>
    func synthesizePreview(ssml: String, language: String) async throws -> Data
}
