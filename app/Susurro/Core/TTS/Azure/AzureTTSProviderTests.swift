import Testing
import Foundation
@testable import Susurro

// MARK: - Mock URLProtocol

nonisolated(unsafe) private var azureMockResponseData: Data = Data()
nonisolated(unsafe) private var azureMockStatusCode: Int = 200
nonisolated(unsafe) private var azureMockCapturedRequest: URLRequest? = nil
nonisolated(unsafe) private var azureMockDelay: TimeInterval = 0

private final class AzureMockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        azureMockCapturedRequest = request

        if azureMockDelay > 0 {
            Thread.sleep(forTimeInterval: azureMockDelay)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: azureMockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: azureMockResponseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeMockSession(
    data: Data = Data(),
    statusCode: Int = 200,
    delay: TimeInterval = 0
) -> URLSession {
    azureMockResponseData = data
    azureMockStatusCode = statusCode
    azureMockCapturedRequest = nil
    azureMockDelay = delay
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AzureMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeProvider(
    key: String? = "fake-key",
    region: String? = "eastus",
    session: URLSession = makeMockSession()
) -> AzureTTSProvider {
    AzureTTSProvider(
        keyProvider: { key },
        regionProvider: { region },
        session: session,
        pronunciationsApply: { text, _ in text }   // no-op for unit tests
    )
}

/// Reads body from a URLRequest, handling both httpBody and httpBodyStream,
/// since URLSession sometimes migrates httpBody → httpBodyStream when using bytes(for:).
private func requestBodyString(_ request: URLRequest?) -> String {
    guard let req = request else { return "" }
    if let data = req.httpBody {
        return String(data: data, encoding: .utf8) ?? ""
    }
    if let stream = req.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(contentsOf: buffer[0..<bytesRead])
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    return ""
}

// MARK: - Tests

@Suite("AzureTTSProvider", .serialized)
struct AzureTTSProviderTests {

    // MARK: warmup

    @Test("warmup throws azureNotConfigured when key is nil")
    func warmupRequiresKey() async throws {
        let provider = makeProvider(key: nil)
        await #expect(throws: BackendError.azureNotConfigured) {
            try await provider.warmup()
        }
    }

    @Test("warmup throws azureNotConfigured when key is empty")
    func warmupRequiresNonEmptyKey() async throws {
        let provider = makeProvider(key: "")
        await #expect(throws: BackendError.azureNotConfigured) {
            try await provider.warmup()
        }
    }

    @Test("warmup throws azureNotConfigured when region is nil")
    func warmupRequiresRegion() async throws {
        let provider = makeProvider(region: nil)
        await #expect(throws: BackendError.azureNotConfigured) {
            try await provider.warmup()
        }
    }

    @Test("warmup succeeds when key and region are both set")
    func warmupSucceeds() async throws {
        let provider = makeProvider()
        try await provider.warmup()   // must not throw
    }

    // MARK: synthesize — request shape

    @Test("synthesize builds correct URL and headers")
    func synthesizeBuildsCorrectRequest() async throws {
        let session = makeMockSession(data: Data("audio".utf8))
        let provider = makeProvider(key: "fake-key", region: "eastus", session: session)

        _ = try await provider.synthesize(text: "Hola", language: "es")

        let req = azureMockCapturedRequest
        #expect(req?.url?.absoluteString == "https://eastus.tts.speech.microsoft.com/cognitiveservices/v1")
        #expect(req?.httpMethod == "POST")
        #expect(req?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "fake-key")
        #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/ssml+xml")
        #expect(req?.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "audio-24khz-48kbitrate-mono-mp3")
        #expect(req?.value(forHTTPHeaderField: "User-Agent") == "susurro")
    }

    @Test("synthesize request body contains correct SSML for Spanish")
    func synthesizeRequestBodyHasSpanishSSML() async throws {
        let session = makeMockSession(data: Data("audio".utf8))
        let provider = makeProvider(session: session)

        _ = try await provider.synthesize(text: "Hola", language: "es")

        // URLSession may move httpBody → httpBodyStream when using bytes(for:).
        let body = requestBodyString(azureMockCapturedRequest)
        #expect(body.contains("xml:lang='es-ES'"))
        #expect(body.contains("name='es-ES-AlvaroNeural'"))
        #expect(body.contains("<speak"))
    }

    // MARK: synthesize — response

    @Test("synthesize returns full response bytes")
    func synthesizeReturnsResponseBytes() async throws {
        let fixture = Data(repeating: 0xAB, count: 256)
        let session = makeMockSession(data: fixture)
        let provider = makeProvider(session: session)

        let result = try await provider.synthesize(text: "Hello", language: "en")
        #expect(result == fixture)
    }

    @Test("synthesize with non-200 status throws extractFailed")
    func synthesizeNon200ThrowsExtractFailed() async throws {
        let session = makeMockSession(data: Data("unauthorized".utf8), statusCode: 401)
        let provider = makeProvider(session: session)

        await #expect(throws: BackendError.extractFailed("azure http 401")) {
            try await provider.synthesize(text: "Hello", language: "en")
        }
    }

    @Test("synthesize with invalid language throws extractFailed")
    func synthesizeInvalidLanguageThrows() async throws {
        let provider = makeProvider()
        await #expect(throws: BackendError.extractFailed("invalid language")) {
            try await provider.synthesize(text: "Bonjour", language: "fr")
        }
    }

    @Test("synthesize throws azureNotConfigured when key missing at call time")
    func synthesizeMissingKeyThrows() async throws {
        let provider = makeProvider(key: nil)
        await #expect(throws: BackendError.azureNotConfigured) {
            try await provider.synthesize(text: "Hello", language: "en")
        }
    }

    // MARK: synthesizeStream

    @Test("synthesizeStream yields exactly one chunk")
    func synthesizeStreamYieldsSingleChunk() async throws {
        let fixture = Data(repeating: 0xCC, count: 128)
        let session = makeMockSession(data: fixture)
        let provider = makeProvider(session: session)

        var chunks: [Data] = []
        for try await chunk in provider.synthesizeStream(text: "Hello", language: "en") {
            chunks.append(chunk)
        }
        #expect(chunks.count == 1)
        #expect(chunks[0] == fixture)
    }

    // MARK: synthesizeChunks

    @Test("synthesizeChunks processes all chunks and yields one Data per chunk")
    func synthesizeChunksProcessesAllChunks() async throws {
        let fixture = Data(repeating: 0xDD, count: 64)
        let session = makeMockSession(data: fixture)
        let provider = makeProvider(session: session)

        let chunks = ["chunk one", "chunk two", "chunk three"]
        var results: [Data] = []
        for try await data in provider.synthesizeChunks(chunks, language: "en") {
            results.append(data)
        }
        #expect(results.count == 3)
    }

    @Test("synthesizeChunks with empty array yields no data")
    func synthesizeChunksEmptyArray() async throws {
        let provider = makeProvider()
        var count = 0
        for try await _ in provider.synthesizeChunks([], language: "en") {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: synthesizeChunked

    @Test("synthesizeChunked uses Chunker to split text")
    func synthesizeChunkedUsesChunker() async throws {
        // Build a text that Chunker would split into multiple chunks
        let sentence = "This is a sentence that fills up space."
        let text = Array(repeating: sentence, count: 15).joined(separator: " ")
        let expectedChunkCount = Chunker.chunk(text).count
        #expect(expectedChunkCount > 1)

        let fixture = Data(repeating: 0xEE, count: 32)
        let session = makeMockSession(data: fixture)
        let provider = makeProvider(session: session)

        var count = 0
        for try await _ in provider.synthesizeChunked(text: text, language: "en") {
            count += 1
        }
        #expect(count == expectedChunkCount)
    }

    // MARK: synthesizePreview

    @Test("synthesizePreview POSTs raw SSML fragment without modification")
    func synthesizePreviewPostsRawFragment() async throws {
        let session = makeMockSession(data: Data("audio".utf8))
        let provider = makeProvider(session: session)

        let fragment = "<phoneme alphabet=\"ipa\" ph=\"hə.ˈloʊ\">hello</phoneme>"
        _ = try await provider.synthesizePreview(ssml: fragment, language: "en")

        // URLSession may move httpBody → httpBodyStream when using bytes(for:).
        let body = requestBodyString(azureMockCapturedRequest)
        #expect(body.contains(fragment))
        // No break injection should have fired
        #expect(!body.contains("<break"))
    }

    // MARK: cancellation

    @Test("task cancelled before synthesize throws generationCancelled")
    func cancelTaskBeforeSynthesizeThrowsGenerationCancelled() async throws {
        let provider = makeProvider()

        let task = Task<Data, Error> {
            try await provider.synthesize(text: "Hello", language: "en")
        }
        task.cancel()
        let result = await task.result

        switch result {
        case .failure(let error as BackendError):
            #expect(error == .generationCancelled)
        case .failure:
            Issue.record("Expected BackendError.generationCancelled, got different error")
        case .success:
            Issue.record("Expected task to be cancelled but it succeeded")
        }
    }
}
