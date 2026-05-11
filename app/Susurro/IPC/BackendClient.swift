import Foundation

actor BackendClient {
    static let shared = BackendClient()

    private let extractor: ArticleExtractor
    private let pronunciations: PronunciationStore
    /// Overrides TTS synthesis for testing. When non-nil, `tts` and `streamingTTS` use this closure instead of the registry.
    let ttsOverride: (@Sendable (String, String) async throws -> Data)?

    init(
        extractor: ArticleExtractor = ArticleExtractor(),
        pronunciations: PronunciationStore = .shared,
        ttsOverride: (@Sendable (String, String) async throws -> Data)? = nil
    ) {
        self.extractor = extractor
        self.pronunciations = pronunciations
        self.ttsOverride = ttsOverride
    }

    // MARK: - Health

    func health() async -> HealthStatus {
        let ready = await MainActor.run { TTSProviderRegistry.shared.isReady }
        return ready ? .ready : .loading
    }

    // MARK: - TTS (one-shot)

    func tts(text: String, language: String?) async throws -> Data {
        let lang = language ?? LangDetect.detect(text)
        if let override = ttsOverride {
            return try await override(text, lang)
        }
        let provider = await MainActor.run { TTSProviderRegistry.shared.current }
        return try await provider.synthesize(text: text, language: lang)
    }

    // MARK: - TTS (streaming via chunks)

    nonisolated func streamingTTS(
        text: String,
        language: String?,
        startChunk: Int = 0
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lang = language ?? LangDetect.detect(text)
                    let override = await self.ttsOverride
                    if let override {
                        let data = try await override(text, lang)
                        continuation.yield(data)
                        continuation.finish()
                        return
                    }
                    let chunks = Chunker.chunk(text)
                    let sliced = startChunk > 0 && startChunk < chunks.count
                        ? Array(chunks[startChunk...])
                        : chunks
                    let provider = await MainActor.run { TTSProviderRegistry.shared.current }
                    for try await data in provider.synthesizeChunks(sliced, language: lang) {
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchChunks(text: String, language: String?) async -> (chunks: [String], language: String) {
        let lang = language ?? LangDetect.detect(text)
        return (Chunker.chunk(text), lang)
    }

    // MARK: - Pronunciations

    func listPronunciations() async -> [String: [String: String]] {
        await pronunciations.listAll()
    }

    func upsertPronunciation(language: String, word: String, replacement: String) async throws {
        try await pronunciations.upsert(language: language, word: word, replacement: replacement)
    }

    func deletePronunciation(language: String, word: String) async throws -> Bool {
        try await pronunciations.remove(language: language, word: word)
    }

    func pronunciationCandidates(word: String, language: String) async -> [PronunciationCandidate] {
        await pronunciations.candidates(word: word, language: language)
    }

    func pronunciationCandidatesEdgeSafe(word: String, language: String) async -> [PronunciationCandidate] {
        await pronunciations.candidatesEdgeSafe(word: word, language: language)
    }

    // MARK: - SSML preview (Azure only)

    func previewSSML(ssml: String, language: String) async throws -> Data {
        let provider = await MainActor.run { TTSProviderRegistry.shared.current }
        guard provider is AzureTTSProvider else {
            throw BackendError.azureNotConfigured
        }
        return try await provider.synthesizePreview(ssml: ssml, language: language)
    }

    // MARK: - Plain-text preview (Edge only)

    /// Synthesizes a short plain-text sentence using the given word via Edge TTS.
    /// Throws `BackendError.invalidProvider` when the active provider is not Edge.
    func previewEdgeSafe(word: String, language: String) async throws -> Data {
        let provider = await MainActor.run { TTSProviderRegistry.shared.current }
        guard provider is EdgeTTSProvider else {
            throw BackendError.invalidProvider("Edge required for edge-safe preview")
        }
        return try await provider.synthesize(text: word, language: language)
    }

    // MARK: - Extract

    func extract(url: String) async throws -> ExtractedArticle {
        try await extractor.extract(url: url)
    }

    // MARK: - Stop (no-op; PlaybackCoordinator cancels its own Task)

    nonisolated func stop() { }
}
