import Foundation
import Network

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

    /// Default URLSession configured for Edge WebSocket: ephemeral cache,
    /// no cookies, no credential storage. Avoids URLSession.shared caching
    /// that can leak stale connections.
    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    init(
        urlSession: URLSession? = nil,
        signer: EdgeSigningClock = SystemEdgeSigningClock(),
        pronunciationsApply: @escaping @Sendable (String, String) async -> String = { text, lang in
            await PronunciationStore.shared.apply(text: text, language: lang)
        },
        urlBuilder: (@Sendable (String) -> URL)? = nil
    ) {
        self.urlSession = urlSession ?? Self.makeDefaultSession()
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

        // Use Network framework's NWConnection + NWProtocolWebSocket directly.
        // URLSessionWebSocketTask negotiates HTTP/2 ALPN and the Microsoft Edge
        // TTS endpoint rejects the resulting Extended CONNECT upgrade with
        // POSIX 57 ("Socket is not connected"). NWConnection issues a plain
        // HTTP/1.1 Upgrade which Microsoft accepts.
        let ws = try await EdgeWS.connect(url: wsURL)

        return try await withTaskCancellationHandler {
            try await doSynthesize(ws: ws, connectionId: connectionId, ssmlEnvelope: ssmlEnvelope)
        } onCancel: {
            ws.cancel()
        }
    }

    // MARK: - Core WebSocket interaction

    /// Drives the full Edge TTS WebSocket exchange once the connection is established.
    ///
    /// Separated from `performSynthesize` so `withTaskCancellationHandler` can cancel
    /// the `URLSessionWebSocketTask` at any suspension point (including `receive()`).
    private func doSynthesize(
        ws: EdgeWS,
        connectionId: String,
        ssmlEnvelope: String
    ) async throws -> Data {
        do {
            try Task.checkCancellation()

            let timestamp = jsDateNow()
            let configPayload =
                "X-Timestamp:\(timestamp)\r\n" +
                "Content-Type:application/json; charset=utf-8\r\n" +
                "Path:speech.config\r\n\r\n" +
                "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{" +
                "\"sentenceBoundaryEnabled\":\"true\",\"wordBoundaryEnabled\":\"false\"}," +
                "\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"

            try await ws.sendText(configPayload)
            try Task.checkCancellation()

            let ssmlTimestamp = jsDateNow()
            let ssmlPayload =
                "X-RequestId:\(connectionId)\r\n" +
                "Content-Type:application/ssml+xml\r\n" +
                "X-Timestamp:\(ssmlTimestamp)Z\r\n" +
                "Path:ssml\r\n\r\n" +
                ssmlEnvelope

            try await ws.sendText(ssmlPayload)
            try Task.checkCancellation()

            var audioBuffer = Data()
            receiveLoop: while true {
                try Task.checkCancellation()
                let message = try await ws.receive()
                switch message {
                case .data(let d):
                    if let parsed = EdgeFrameParser.parseBinaryFrame(d),
                       parsed.path == "audio" {
                        audioBuffer.append(parsed.audio)
                    }
                case .text(let s):
                    let parsed = EdgeFrameParser.parseTextFrame(s)
                    if parsed.path == "turn.end" {
                        break receiveLoop
                    }
                }
            }

            ws.cancel()
            return audioBuffer

        } catch is CancellationError {
            ws.cancel()
            throw BackendError.generationCancelled
        } catch let error as BackendError {
            ws.cancel()
            throw error
        } catch {
            ws.cancel()
            if Task.isCancelled {
                throw BackendError.generationCancelled
            }
            throw error
        }
    }

    // MARK: - Helpers

    /// Matches JavaScript's `Date.toString()` output, which is what
    /// Microsoft's Edge endpoint expects for `X-Timestamp`.
    /// Example: "Tue May 05 2026 11:25:21 GMT+0000 (Coordinated Universal Time)"
    private func jsDateNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date()) + " GMT+0000 (Coordinated Universal Time)"
    }
}

// MARK: - EdgeWS — manual RFC 6455 WebSocket over TCP+TLS

/// A WebSocket client implementing RFC 6455 manually on top of a plain
/// TCP+TLS `NWConnection`.
///
/// Why hand-rolled?
/// - `URLSessionWebSocketTask` negotiates HTTP/2 ALPN and uses Extended
///   CONNECT (RFC 8441); Microsoft's Edge TTS endpoint rejects that.
/// - `NWProtocolWebSocket` does not support `permessage-deflate` and Network
///   framework auto-promotes the connection to QUIC/HTTP-3 even when only
///   `http/1.1` is advertised in ALPN.
///
/// This implementation owns the WS framing entirely so we can present the
/// exact upgrade request shape Microsoft expects.
import CryptoKit

actor EdgeWS {
    enum Message: Sendable {
        case text(String)
        case data(Data)
    }

    enum WSError: Error, CustomStringConvertible {
        case connectFailed(Error)
        case sendFailed(Error)
        case receiveFailed(Error)
        case closed
        case badHandshake(String)
        case invalidFrame(String)

        var description: String {
            switch self {
            case .connectFailed(let e): return "connectFailed: \(e)"
            case .sendFailed(let e):    return "sendFailed: \(e)"
            case .receiveFailed(let e): return "receiveFailed: \(e)"
            case .closed:               return "closed"
            case .badHandshake(let m):  return "badHandshake: \(m)"
            case .invalidFrame(let m):  return "invalidFrame: \(m)"
            }
        }
    }

    private nonisolated let connection: NWConnection
    private nonisolated let connectionQueue: DispatchQueue
    private var rxBuffer = Data()

    /// Magic GUID concatenated with the client's `Sec-WebSocket-Key`,
    /// SHA-1 hashed, base64-encoded — must match the server's
    /// `Sec-WebSocket-Accept`. RFC 6455 §1.3.
    private static let wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    private init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.connectionQueue = queue
    }

    // MARK: - Connect + Handshake

    static func connect(url: URL) async throws -> EdgeWS {
        guard let scheme = url.scheme, scheme == "ws" || scheme == "wss" else {
            throw WSError.connectFailed(URLError(.badURL))
        }
        guard let urlHost = url.host else {
            throw WSError.connectFailed(URLError(.badURL))
        }
        let useTLS = (scheme == "wss")
        let host = NWEndpoint.Host(urlHost)
        let defaultPort: NWEndpoint.Port = useTLS ? .https : .http
        let port: NWEndpoint.Port = url.port.flatMap { NWEndpoint.Port(rawValue: UInt16($0)) }
            ?? defaultPort

        // TCP+TLS parameters with ALPN restricted to http/1.1 to forbid HTTP/2
        // and HTTP/3 promotion.
        let tcpOptions = NWProtocolTCP.Options()
        let params: NWParameters
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_add_tls_application_protocol(
                tlsOptions.securityProtocolOptions, "http/1.1")
            params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            params = NWParameters(tls: nil, tcp: tcpOptions)
        }
        // No `NWProtocolWebSocket` here — we own the framing layer.

        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let queue = DispatchQueue(label: "susurro.edgews.\(UUID().uuidString)")
        let connection = NWConnection(to: endpoint, using: params)
        let ws = EdgeWS(connection: connection, queue: queue)

        try await ws.startAndWaitReady()
        try await ws.performHandshake(host: urlHost, path: url.path + (url.query.map { "?\($0)" } ?? ""))
        return ws
    }

    private func startAndWaitReady() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let settled = ContinuationLatch(continuation: cont)
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    settled.fulfill(.success(()))
                case .failed(let err), .waiting(let err):
                    connection?.cancel()
                    settled.fulfill(.failure(WSError.connectFailed(err)))
                case .cancelled:
                    settled.fulfill(.failure(WSError.closed))
                default:
                    break
                }
            }
            connection.start(queue: connectionQueue)
        }
    }

    private func performHandshake(host: String, path: String) async throws {
        // Generate a random 16-byte client key per RFC 6455 §4.1.
        var keyBytes = Data(count: 16)
        keyBytes.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let clientKey = keyBytes.base64EncodedString()

        // Mirror upstream edge-tts handshake headers byte-for-byte.
        let request =
            "GET \(path.isEmpty ? "/" : path) HTTP/1.1\r\n"
            + "Host: \(host)\r\n"
            + "Connection: Upgrade\r\n"
            + "Pragma: no-cache\r\n"
            + "Cache-Control: no-cache\r\n"
            + "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            + " (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0\r\n"
            + "Upgrade: websocket\r\n"
            + "Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold\r\n"
            + "Sec-WebSocket-Version: 13\r\n"
            + "Accept-Encoding: gzip, deflate, br\r\n"
            + "Accept-Language: en-US,en;q=0.9\r\n"
            + "Sec-WebSocket-Key: \(clientKey)\r\n"
            + "\r\n"

        try await tcpSend(Data(request.utf8))
        try await readUpgradeResponse(expectedKey: clientKey)
    }

    private func readUpgradeResponse(expectedKey: String) async throws {
        // Read until `\r\n\r\n` ends the headers.
        let terminator = Data("\r\n\r\n".utf8)
        while rxBuffer.range(of: terminator) == nil {
            let chunk = try await tcpReceive(min: 1, max: 65536)
            rxBuffer.append(chunk)
            if rxBuffer.count > 64 * 1024 {
                throw WSError.badHandshake("response too large")
            }
        }
        let split = rxBuffer.range(of: terminator)!
        let headerData = rxBuffer.prefix(split.lowerBound)
        rxBuffer.removeSubrange(0..<split.upperBound)

        guard let headerText = String(data: Data(headerData), encoding: .utf8) else {
            throw WSError.badHandshake("non-utf8 response")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw WSError.badHandshake("empty response") }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard statusParts.count >= 2, let code = Int(statusParts[1]) else {
            throw WSError.badHandshake("bad status: \(statusLine)")
        }
        guard code == 101 else {
            throw WSError.badHandshake("HTTP \(code): \(statusLine)")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }
        guard headers["upgrade"]?.lowercased() == "websocket" else {
            throw WSError.badHandshake("missing/bad Upgrade header")
        }
        guard headers["connection"]?.lowercased().contains("upgrade") == true else {
            throw WSError.badHandshake("missing/bad Connection header")
        }
        guard let accept = headers["sec-websocket-accept"] else {
            throw WSError.badHandshake("missing Sec-WebSocket-Accept")
        }
        let expected = expectedAcceptValue(forKey: expectedKey)
        guard accept == expected else {
            throw WSError.badHandshake("Sec-WebSocket-Accept mismatch")
        }
    }

    private func expectedAcceptValue(forKey key: String) -> String {
        let combined = key + Self.wsGUID
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }

    // MARK: - Public send

    func sendText(_ string: String) async throws {
        try await sendFrame(opcode: 0x1, payload: Data(string.utf8))
    }

    func sendData(_ data: Data) async throws {
        try await sendFrame(opcode: 0x2, payload: data)
    }

    nonisolated func cancel() {
        connection.cancel()
    }

    // MARK: - Public receive

    /// Returns the next complete WebSocket message. Handles ping/pong
    /// transparently; throws `.closed` on close frame; concatenates
    /// continuation frames per RFC 6455 §5.4.
    func receive() async throws -> Message {
        var buffer = Data()
        var firstOpcode: UInt8 = 0
        while true {
            let frame = try await readFrame()
            switch frame.opcode {
            case 0x0:
                buffer.append(frame.payload)
                if frame.fin {
                    return try assemble(opcode: firstOpcode, data: buffer)
                }
            case 0x1, 0x2:
                if frame.fin {
                    return try assemble(opcode: frame.opcode, data: frame.payload)
                }
                firstOpcode = frame.opcode
                buffer = frame.payload
            case 0x8: // close
                try? await sendFrame(opcode: 0x8, payload: Data())
                throw WSError.closed
            case 0x9: // ping → pong
                try await sendFrame(opcode: 0xA, payload: frame.payload)
            case 0xA: // pong
                continue
            default:
                throw WSError.invalidFrame("opcode \(frame.opcode)")
            }
        }
    }

    private func assemble(opcode: UInt8, data: Data) throws -> Message {
        if opcode == 0x1 {
            return .text(String(data: data, encoding: .utf8) ?? "")
        }
        return .data(data)
    }

    // MARK: - Frame protocol (RFC 6455 §5.2)

    private struct FrameHeader {
        var fin: Bool
        var opcode: UInt8
        var payload: Data
    }

    private func readFrame() async throws -> FrameHeader {
        let head = try await readExact(2)
        let b0 = head[head.startIndex]
        let b1 = head[head.startIndex + 1]
        let fin = (b0 & 0x80) != 0
        let opcode = b0 & 0x0F
        let masked = (b1 & 0x80) != 0
        let len7 = b1 & 0x7F

        let length: Int
        switch len7 {
        case 0...125:
            length = Int(len7)
        case 126:
            let ext = try await readExact(2)
            length = (Int(ext[ext.startIndex]) << 8) | Int(ext[ext.startIndex + 1])
        default:
            let ext = try await readExact(8)
            var n: UInt64 = 0
            for i in 0..<8 { n = (n << 8) | UInt64(ext[ext.startIndex + i]) }
            if n > UInt64(Int.max) { throw WSError.invalidFrame("oversized payload") }
            length = Int(n)
        }

        var maskKey = Data()
        if masked {
            maskKey = try await readExact(4)
        }
        var payload = try await readExact(length)
        if masked {
            for i in 0..<payload.count {
                payload[payload.startIndex + i] ^= maskKey[maskKey.startIndex + (i % 4)]
            }
        }
        return FrameHeader(fin: fin, opcode: opcode, payload: payload)
    }

    private func sendFrame(opcode: UInt8, payload: Data) async throws {
        var frame = Data()
        frame.append(0x80 | opcode) // FIN=1
        let len = payload.count
        let maskBit: UInt8 = 0x80
        if len < 126 {
            frame.append(maskBit | UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(maskBit | 126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(maskBit | 127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((UInt64(len) >> (i * 8)) & 0xFF))
            }
        }

        var mask = Data(count: 4)
        mask.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
        frame.append(mask)

        var masked = payload
        for i in 0..<masked.count {
            masked[masked.startIndex + i] ^= mask[mask.startIndex + (i % 4)]
        }
        frame.append(masked)
        try await tcpSend(frame)
    }

    // MARK: - TCP I/O bridges

    private func readExact(_ n: Int) async throws -> Data {
        if n == 0 { return Data() }
        while rxBuffer.count < n {
            let chunk = try await tcpReceive(min: 1, max: max(n - rxBuffer.count, 65536))
            if chunk.isEmpty { throw WSError.closed }
            rxBuffer.append(chunk)
        }
        let result = Data(rxBuffer.prefix(n))
        rxBuffer.removeSubrange(0..<n)
        return result
    }

    private nonisolated func tcpReceive(min: Int, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let settled = ContinuationLatch(continuation: cont)
            connection.receive(minimumIncompleteLength: min, maximumLength: max) { content, _, isComplete, error in
                if let error {
                    settled.fulfill(.failure(WSError.receiveFailed(error)))
                    return
                }
                if let content, !content.isEmpty {
                    settled.fulfill(.success(content))
                    return
                }
                if isComplete {
                    settled.fulfill(.failure(WSError.closed))
                    return
                }
                settled.fulfill(.success(Data()))
            }
        }
    }

    private nonisolated func tcpSend(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let settled = ContinuationLatch(continuation: cont)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    settled.fulfill(.failure(WSError.sendFailed(error)))
                } else {
                    settled.fulfill(.success(()))
                }
            })
        }
    }
}

// MARK: - Continuation latch — guards against double-resume on stateful callbacks

private final class ContinuationLatch<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<T, Error>

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func fulfill(_ result: Result<T, Error>) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
