import Foundation
import Network
import Testing
@testable import Susurro

// MARK: - Mock WebSocket server

/// A WebSocket server using NWProtocolWebSocket (Network framework) for testing.
/// Handles one connection at a time; `handler` is called with each accepted NWConnection.
private final class MockWSServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: @Sendable (NWConnection) async -> Void
    private let queue = DispatchQueue(label: "mock-ws-server", qos: .userInitiated)

    init(handler: @escaping @Sendable (NWConnection) async -> Void) throws {
        self.handler = handler
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        self.listener = try NWListener(using: params)
        startListening()
    }

    private func startListening() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            Task { await self.handler(connection) }
        }
        listener.start(queue: queue)
    }

    func resolvedPort() async -> UInt16 {
        for _ in 0 ..< 100 {
            if listener.state == .ready, let p = listener.port?.rawValue, p != 0 {
                return p
            }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        return listener.port?.rawValue ?? 0
    }

    func cancel() { listener.cancel() }
}

// MARK: - NWConnection WebSocket helpers

/// Sends a WebSocket text message on a server-side NWConnection.
private func sendTextMessage(_ text: String, on connection: NWConnection) async throws {
    let data = Data(text.utf8)
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(
        identifier: "text",
        metadata: [metadata]
    )
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { err in
            if let err { cont.resume(throwing: err) } else { cont.resume() }
        })
    }
}

/// Sends a WebSocket binary message on a server-side NWConnection.
private func sendBinaryMessage(_ data: Data, on connection: NWConnection) async throws {
    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
    let context = NWConnection.ContentContext(
        identifier: "binary",
        metadata: [metadata]
    )
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { err in
            if let err { cont.resume(throwing: err) } else { cont.resume() }
        })
    }
}

/// Reads the next WebSocket message from a server-side NWConnection.
/// Returns `(opcode, data)` or throws on error/close.
private func receiveMessage(on connection: NWConnection) async throws -> (NWProtocolWebSocket.Opcode, Data) {
    try await withCheckedThrowingContinuation { cont in
        connection.receiveMessage { content, context, _, error in
            if let error {
                cont.resume(throwing: error)
                return
            }
            let payload = content ?? Data()
            if let wsCtx = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata {
                cont.resume(returning: (wsCtx.opcode, payload))
            } else {
                cont.resume(returning: (.binary, payload))
            }
        }
    }
}

// MARK: - Binary audio frame builder

/// Builds an Edge TTS binary audio frame: 2-byte big-endian header length + ASCII headers + audio.
private func makeBinaryAudioFrame(audioBytes: Data) -> Data {
    let headerStr = "Path:audio\r\nContent-Type:audio/mpeg\r\n"
    let headerData = headerStr.data(using: .ascii)!
    let headerLen = UInt16(headerData.count)

    var frame = Data()
    frame.append(UInt8(headerLen >> 8))
    frame.append(UInt8(headerLen & 0xFF))
    frame.append(contentsOf: headerData)
    frame.append(contentsOf: audioBytes)
    return frame
}

// MARK: - Provider factory

private func makeProvider(port: UInt16) -> EdgeTTSProvider {
    EdgeTTSProvider(
        urlSession: .shared,
        signer: SystemEdgeSigningClock(),
        pronunciationsApply: { text, _ in text },
        urlBuilder: { _ in URL(string: "ws://127.0.0.1:\(port)/")! }
    )
}

// MARK: - Standard mock server script (happy path)

private func runHappyPathServer(connection: NWConnection, audioBytes: Data) async {
    // Consume the speech.config frame
    _ = try? await receiveMessage(on: connection)
    // Consume the ssml frame
    _ = try? await receiveMessage(on: connection)

    // Send turn.start
    try? await sendTextMessage("Path:turn.start\r\n\r\n{}", on: connection)
    // Send audio binary frame
    let audioFrame = makeBinaryAudioFrame(audioBytes: audioBytes)
    try? await sendBinaryMessage(audioFrame, on: connection)
    // Send turn.end
    try? await sendTextMessage("Path:turn.end\r\n\r\n", on: connection)

    // Give URLSession a moment to drain then close
    try? await Task.sleep(nanoseconds: 50_000_000)
    connection.cancel()
}

// MARK: - Tests

@Suite("EdgeTTSProvider", .serialized)
struct EdgeTTSProviderTests {

    // MARK: - Invalid language (no network needed)

    @Test("synthesize throws extractFailed for unsupported language")
    func invalidLanguageThrows() async throws {
        let provider = EdgeTTSProvider(
            urlBuilder: { _ in URL(string: "ws://127.0.0.1:9/")! }
        )
        await #expect(throws: BackendError.extractFailed("invalid language")) {
            try await provider.synthesize(text: "Bonjour", language: "fr")
        }
    }

    // MARK: - synthesizePreview (no network needed)

    @Test("synthesizePreview throws azureNotConfigured")
    func synthesizePreviewThrows() async throws {
        let provider = EdgeTTSProvider(
            urlBuilder: { _ in URL(string: "ws://127.0.0.1:9/")! }
        )
        await #expect(throws: BackendError.azureNotConfigured) {
            try await provider.synthesizePreview(ssml: "<speak/>", language: "en")
        }
    }

    // MARK: - Happy path

    @Test("synthesize returns audio bytes from mock server")
    func synthesizeHappyPath() async throws {
        let audioPayload = Data(repeating: 0xAA, count: 1024)
        let server = try MockWSServer { connection in
            await runHappyPathServer(connection: connection, audioBytes: audioPayload)
        }
        let port = await server.resolvedPort()
        defer { server.cancel() }

        let provider = makeProvider(port: port)
        let result = try await provider.synthesize(text: "hola", language: "es")
        #expect(result.count == 1024)
    }

    // MARK: - synthesizeStream

    @Test("synthesizeStream yields exactly one chunk")
    func synthesizeStreamYieldsSingleChunk() async throws {
        let audioPayload = Data(repeating: 0xBB, count: 512)
        let server = try MockWSServer { connection in
            await runHappyPathServer(connection: connection, audioBytes: audioPayload)
        }
        let port = await server.resolvedPort()
        defer { server.cancel() }

        let provider = makeProvider(port: port)
        var chunks: [Data] = []
        for try await chunk in provider.synthesizeStream(text: "hello", language: "en") {
            chunks.append(chunk)
        }
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 512)
    }

    // MARK: - synthesizeChunks

    @Test("synthesizeChunks yields one Data per chunk")
    func synthesizeChunksTwoChunks() async throws {
        let audioPayload = Data(repeating: 0xCC, count: 256)
        let server = try MockWSServer { connection in
            await runHappyPathServer(connection: connection, audioBytes: audioPayload)
        }
        let port = await server.resolvedPort()
        defer { server.cancel() }

        let provider = makeProvider(port: port)
        var results: [Data] = []
        for try await data in provider.synthesizeChunks(["hola", "mundo"], language: "es") {
            results.append(data)
        }
        // Each chunk gets its own connection; each yields one Data
        #expect(results.count == 2)
    }

    // MARK: - Production URL includes Sec-MS-GEC params

    @Test("productionURL contains Sec-MS-GEC and Sec-MS-GEC-Version params")
    func productionURLContainsSecMSGECParams() {
        // Fixed instant: 2023-11-14T22:13:20Z
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let url = EdgeURLBuilder.production(connectionId: "test", now: fixedDate)
        let urlStr = url.absoluteString

        // Token computed by EdgeAuthSigner for this timestamp (locked against Python reference)
        let expectedGEC = "42301B335578FEFDAE2637DED1ABD614505D432559EC08032B82048483726AFF"
        let expectedVersion = "1-130.0.2849.68"

        #expect(urlStr.contains("Sec-MS-GEC=\(expectedGEC)"),
                "URL missing Sec-MS-GEC param: \(urlStr)")
        #expect(urlStr.contains("Sec-MS-GEC-Version=\(expectedVersion)"),
                "URL missing Sec-MS-GEC-Version param: \(urlStr)")
        #expect(urlStr.contains("TrustedClientToken="),
                "URL missing TrustedClientToken param: \(urlStr)")
        #expect(urlStr.contains("ConnectionId=test"),
                "URL missing ConnectionId param: \(urlStr)")
    }

    // MARK: - Cancellation

    @Test("cancelled task throws generationCancelled")
    func cancellationThrowsGenerationCancelled() async throws {
        // Server reads frames then stalls indefinitely without sending turn.end
        let server = try MockWSServer { connection in
            _ = try? await receiveMessage(on: connection)
            _ = try? await receiveMessage(on: connection)
            // Hold connection open for 30s so the client must cancel
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            connection.cancel()
        }
        let port = await server.resolvedPort()
        defer { server.cancel() }

        let provider = makeProvider(port: port)
        let task = Task<Data, Error> {
            try await provider.synthesize(text: "hola", language: "es")
        }

        // Cancel after 200ms
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let result = await task.result
        switch result {
        case .failure(BackendError.generationCancelled):
            break // expected
        case .failure(let e):
            Issue.record("Expected generationCancelled, got \(e)")
        case .success:
            Issue.record("Expected cancellation but got success")
        }
    }
}
