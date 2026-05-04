import Foundation

/// Azure Cognitive Services TTS provider.
///
/// Uses the Azure REST Speech Synthesis endpoint.
/// Key and region are read on every call via closures so that Settings UI
/// changes propagate without re-initializing the provider.
actor AzureTTSProvider: TTSSynthesizer {

    // MARK: - Dependencies

    private let keyProvider: @Sendable () -> String?
    private let regionProvider: @Sendable () -> String?
    private let session: URLSession
    private let pronunciationsApply: @Sendable (String, String) async -> String

    // MARK: - Init

    init(
        keyProvider: @escaping @Sendable () -> String?,
        regionProvider: @escaping @Sendable () -> String?,
        session: URLSession = .shared,
        pronunciationsApply: @escaping @Sendable (String, String) async -> String = { text, lang in
            await PronunciationStore.shared.apply(text: text, language: lang)
        }
    ) {
        self.keyProvider = keyProvider
        self.regionProvider = regionProvider
        self.session = session
        self.pronunciationsApply = pronunciationsApply
    }

    // MARK: - TTSProvider

    func warmup() async throws {
        guard let key = keyProvider(), !key.isEmpty,
              let region = regionProvider(), !region.isEmpty else {
            throw BackendError.azureNotConfigured
        }
    }

    func synthesize(text: String, language: String) async throws -> Data {
        let (key, region) = try resolvedCredentials()
        let (voice, code) = try resolvedVoiceAndCode(for: language)

        var body = await pronunciationsApply(text, language)
        body = BreakInjector.inject(body)
        let ssml = SSMLBuilder.wrap(body: body, code: code, voice: voice)

        let request = buildRequest(ssml: ssml, key: key, region: region)
        return try await fetchData(request: request)
    }

    nonisolated func synthesizeStream(text: String, language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await self.synthesize(text: text, language: language)
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated func synthesizeChunks(_ chunks: [String], language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for chunk in chunks {
                        try Task.checkCancellation()
                        let data = try await self.synthesize(text: chunk, language: language)
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    if error is CancellationError {
                        continuation.finish(throwing: BackendError.generationCancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    nonisolated func synthesizeChunked(text: String, language: String) -> AsyncThrowingStream<Data, Error> {
        synthesizeChunks(Chunker.chunk(text), language: language)
    }

    func synthesizePreview(ssml ssmlFragment: String, language: String) async throws -> Data {
        let (key, region) = try resolvedCredentials()
        let (voice, _) = try resolvedVoiceAndCode(for: language)

        let ssml = SSMLBuilder.azurePreview(ssmlBody: ssmlFragment, language: language, voice: voice)
        let request = buildRequest(ssml: ssml, key: key, region: region)
        return try await fetchData(request: request)
    }

    // MARK: - Private helpers

    private func resolvedCredentials() throws -> (key: String, region: String) {
        guard let key = keyProvider(), !key.isEmpty,
              let region = regionProvider(), !region.isEmpty else {
            throw BackendError.azureNotConfigured
        }
        return (key, region)
    }

    private func resolvedVoiceAndCode(for language: String) throws -> (voice: String, code: String) {
        guard let voice = TTSConstants.voiceByLang[language],
              let code = TTSConstants.langCode[language] else {
            throw BackendError.extractFailed("invalid language")
        }
        return (voice, code)
    }

    private func buildRequest(ssml: String, key: String, region: String) -> URLRequest {
        let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue(TTSConstants.outputFormat, forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("susurro", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(ssml.utf8)
        return request
    }

    private func fetchData(request: URLRequest) async throws -> Data {
        do {
            try Task.checkCancellation()
            let (asyncBytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.extractFailed("invalid response")
            }
            guard httpResponse.statusCode == 200 else {
                throw BackendError.extractFailed("azure http \(httpResponse.statusCode)")
            }

            var accumulated = Data()
            for try await byte in asyncBytes {
                accumulated.append(byte)
                if accumulated.count % (64 * 1024) == 0 {
                    try Task.checkCancellation()
                }
            }
            return accumulated
        } catch let error as BackendError {
            throw error
        } catch is CancellationError {
            throw BackendError.generationCancelled
        } catch {
            throw error
        }
    }
}

