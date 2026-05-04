import Foundation

// MARK: - Clock protocol for DI

/// Abstraction over the system clock so tests can supply deterministic timestamps.
protocol EdgeSigningClock: Sendable {
    func now() -> Date
}

/// Production implementation: returns `Date()`.
struct SystemEdgeSigningClock: EdgeSigningClock {
    func now() -> Date { Date() }
}

// MARK: - URL builder

/// Builds the Edge TTS WebSocket URL. Injected so tests can redirect to a local server.
enum EdgeURLBuilder {
    static func production(connectionId: String, now: Date = Date()) -> URL {
        let token  = EdgeAuthSigner.trustedClientToken
        let gec    = EdgeAuthSigner.signedToken(at: now)
        let gecVer = EdgeAuthSigner.secMSGECVersion
        let base   = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
        let urlStr = "\(base)?TrustedClientToken=\(token)"
            + "&ConnectionId=\(connectionId)"
            + "&Sec-MS-GEC=\(gec)"
            + "&Sec-MS-GEC-Version=\(gecVer)"
        return URL(string: urlStr)!
    }
}

// MARK: - Provider

/// Microsoft Edge TTS provider backed by the reverse-engineered Edge Read Aloud WebSocket API.
///
/// Uses `URLSessionWebSocketTask` for the WebSocket connection; does NOT use `BreakInjector`.
/// Mirrors the Python `tts_edge.py` + upstream `edge-tts` library behaviour.
actor EdgeTTSProvider: TTSProvider {

    // MARK: - Dependencies

    private let urlSession: URLSession
    private let signer: EdgeSigningClock
    private let pronunciationsApply: @Sendable (String, String) async -> String
    private let urlBuilder: @Sendable (String) -> URL

    // MARK: - State

    private(set) var loaded: Bool = false

    // MARK: - Init (production)

    init(
        urlSession: URLSession = .shared,
        signer: EdgeSigningClock = SystemEdgeSigningClock(),
        pronunciationsApply: @escaping @Sendable (String, String) async -> String = { text, lang in
            await PronunciationStore.shared.apply(text: text, language: lang)
        },
        urlBuilder: (@Sendable (String) -> URL)? = nil
    ) {
        self.urlSession = urlSession
        self.signer = signer
        self.pronunciationsApply = pronunciationsApply
        if let urlBuilder {
            self.urlBuilder = urlBuilder
        } else {
            let capturedSigner = signer
            self.urlBuilder = { connectionId in
                EdgeURLBuilder.production(connectionId: connectionId, now: capturedSigner.now())
            }
        }
    }

    // MARK: - TTSProvider

    /// Warms up the connection by synthesizing a silent space in Spanish.
    ///
    /// Unlike the Python implementation, failure here is **not** silently swallowed.
    /// A warmup failure indicates the network or service is unavailable and subsequent
    /// calls would fail anyway.
    func warmup() async throws {
        _ = try await performSynthesize(text: " ", language: "es")
        loaded = true
    }

    /// Synthesizes `text` in `language` and returns the complete MP3 as a single `Data`.
    func synthesize(text: String, language: String) async throws -> Data {
        try await performSynthesize(text: text, language: language)
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

    /// Edge TTS does not support arbitrary SSML preview synthesis.
    ///
    /// Only Azure provides that capability. Callers should gate this behind a provider check.
    func synthesizePreview(ssml: String, language: String) async throws -> Data {
        throw BackendError.azureNotConfigured
    }

    // MARK: - Private implementation

    private func performSynthesize(text: String, language: String) async throws -> Data {
        // Validate language
        guard TTSConstants.voiceByLang[language] != nil else {
            throw BackendError.extractFailed("invalid language")
        }
        let voice = TTSConstants.voiceByLang[language]!

        // Build signed URL
        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let wsURL = urlBuilder(connectionId)

        // Build the SSML payload (uses actor-isolated pronunciationsApply)
        let ssmlEnvelope = await EdgeSSMLBuilder.build(body: text, language: language, voice: voice)

        // Create WebSocket task with the required Origin header
        var urlRequest = URLRequest(url: wsURL)
        urlRequest.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")

        let task = urlSession.webSocketTask(with: urlRequest)
        task.resume()

        // Use withTaskCancellationHandler so that cancelling the parent Task
        // immediately cancels the WebSocket task, unblocking any pending receive().
        return try await withTaskCancellationHandler {
            try await doSynthesize(wsTask: task, connectionId: connectionId, ssmlEnvelope: ssmlEnvelope)
        } onCancel: {
            task.cancel(with: .normalClosure, reason: nil)
        }
    }

    // MARK: - Core WebSocket interaction

    /// Drives the full Edge TTS WebSocket exchange once the connection is established.
    ///
    /// Separated from `performSynthesize` so `withTaskCancellationHandler` can cancel
    /// the `URLSessionWebSocketTask` at any suspension point (including `receive()`).
    private func doSynthesize(
        wsTask: URLSessionWebSocketTask,
        connectionId: String,
        ssmlEnvelope: String
    ) async throws -> Data {
        do {
            try Task.checkCancellation()

            // Send speech.config frame
            let timestamp = rfc1123Now()
            let configPayload =
                "X-Timestamp:\(timestamp)\r\n" +
                "Content-Type:application/json; charset=utf-8\r\n" +
                "Path:speech.config\r\n\r\n" +
                "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{" +
                "\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"}," +
                "\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}}"

            try await wsTask.send(.string(configPayload))
            try Task.checkCancellation()

            // Send ssml frame
            let ssmlTimestamp = rfc1123Now()
            let ssmlPayload =
                "X-RequestId:\(connectionId)\r\n" +
                "Content-Type:application/ssml+xml\r\n" +
                "X-Timestamp:\(ssmlTimestamp)Z\r\n" +
                "Path:ssml\r\n\r\n" +
                ssmlEnvelope

            try await wsTask.send(.string(ssmlPayload))
            try Task.checkCancellation()

            // Receive loop — breaks on turn.end, accumulates audio binary frames
            var audioBuffer = Data()
            receiveLoop: while true {
                try Task.checkCancellation()
                let message = try await wsTask.receive()
                switch message {
                case .data(let d):
                    if let parsed = EdgeFrameParser.parseBinaryFrame(d),
                       parsed.path == "audio" {
                        audioBuffer.append(parsed.audio)
                    }
                case .string(let s):
                    let parsed = EdgeFrameParser.parseTextFrame(s)
                    if parsed.path == "turn.end" {
                        break receiveLoop
                    }
                @unknown default:
                    break
                }
            }

            wsTask.cancel(with: .normalClosure, reason: nil)
            return audioBuffer

        } catch is CancellationError {
            wsTask.cancel(with: .normalClosure, reason: nil)
            throw BackendError.generationCancelled
        } catch let error as BackendError {
            wsTask.cancel(with: .normalClosure, reason: nil)
            throw error
        } catch {
            wsTask.cancel(with: .normalClosure, reason: nil)
            // If the parent Task was cancelled, the WebSocket task's cancellation
            // may surface as a network error rather than CancellationError.
            // Check the task's cancellation state and convert accordingly.
            if Task.isCancelled {
                throw BackendError.generationCancelled
            }
            throw error
        }
    }

    // MARK: - Helpers

    private func rfc1123Now() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
