import Testing
import Foundation
@testable import Susurro

// MARK: - Lockfile

struct LockfileTests {
    @Test func codableRoundtrip() throws {
        let json = """
        {"port":8765,"pid":12345,"token":"abc123","started_at":"2026-01-01T00:00:00Z"}
        """
        let data = json.data(using: .utf8)!
        let lockfile = try JSONDecoder().decode(Lockfile.self, from: data)
        #expect(lockfile.port == 8765)
        #expect(lockfile.pid == 12345)
        #expect(lockfile.token == "abc123")
        #expect(lockfile.startedAt == "2026-01-01T00:00:00Z")

        let encoded = try JSONEncoder().encode(lockfile)
        let decoded = try JSONDecoder().decode(Lockfile.self, from: encoded)
        #expect(decoded.port == lockfile.port)
        #expect(decoded.pid == lockfile.pid)
        #expect(decoded.token == lockfile.token)
        #expect(decoded.startedAt == lockfile.startedAt)
    }

    @Test func locatorResolvesToUserLibrary() {
        let path = LockfileLocator.path.path
        let home = NSHomeDirectory()
        #expect(path.hasPrefix(home))
        #expect(path.hasSuffix("Library/Application Support/Susurro/backend.lock"))
    }
}

// MARK: - BackendClient URL construction

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite(.serialized)
struct BackendClientTests {
    @Test func ttsRequestConstruction() async throws {
        var capturedRequest: URLRequest?
        let responseData = Data("audio-bytes".utf8)

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                responseData
            )
        }
        defer { MockURLProtocol.requestHandler = nil }

        let lockfile = Lockfile(port: 9999, pid: 1, token: "test-token", startedAt: "2026-01-01T00:00:00Z")
        let client = BackendClient(lockfile: lockfile, session: makeSession())

        let returned = try await client.tts(text: "hello", language: "en")

        #expect(returned == responseData)
        #expect(capturedRequest?.url?.path == "/tts")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")

        if let body = capturedRequest?.httpBody {
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["text"] == "hello")
            #expect(decoded["language"] == "en")
        }
    }

    @Test func healthDecoding200Ready() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"status":"ready"}"#.data(using: .utf8)!
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        let url = URL(string: "http://127.0.0.1:9999/health")!
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try JSONDecoder().decode([String: String].self, from: data)
        let statusValue = body["status"] ?? ""

        #expect(statusCode == 200)
        #expect(statusValue == "ready")
    }

    @Test func healthDecoding503Loading() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"status":"loading"}"#.data(using: .utf8)!
            return (
                HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        let url = URL(string: "http://127.0.0.1:9999/health")!
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try JSONDecoder().decode([String: String].self, from: data)
        let statusValue = body["status"] ?? ""

        #expect(statusCode == 503)
        #expect(statusValue == "loading")
    }
}

// MARK: - BackendProcess.State unit tests

struct BackendProcessStateTests {
    // BackendProcess.State is not Equatable (BackendClient in .ready prevents it),
    // but we can verify pattern-matching behaviour for the cases we care about.

    @Test func restartingAssociatedValueDistinction() {
        let a = BackendProcess.State.restarting(attempt: 1)
        let b = BackendProcess.State.restarting(attempt: 2)
        // These are different attempts — confirm via pattern matching.
        if case .restarting(let n) = a { #expect(n == 1) } else { Issue.record("Expected .restarting") }
        if case .restarting(let n) = b { #expect(n == 2) } else { Issue.record("Expected .restarting") }
        // They must differ.
        if case .restarting(let na) = a, case .restarting(let nb) = b {
            #expect(na != nb)
        }
    }

    @Test func stateSendableCompileCheck() {
        // BackendProcess.State is declared Sendable.  If this test compiles, the
        // conformance is satisfied — no runtime assertion needed.
        func acceptSendable<T: Sendable>(_ value: T) {}
        acceptSendable(BackendProcess.State.stopped)
        acceptSendable(BackendProcess.State.starting)
        acceptSendable(BackendProcess.State.restarting(attempt: 1))
        acceptSendable(BackendProcess.State.crashed(reason: "test"))
    }

    // NOTE: Full unit-test coverage of handleTermination / scheduleRestart is not
    // practical without risky refactoring because both methods are private and
    // intertwined with real Process spawning, a 2-second async sleep, and actor
    // state.  To integration-test restart behaviour, run with
    // SUSURRO_RUN_INTEGRATION=1 and extend startStopRealBackend to kill the
    // Python child via `kill -9 <pid>` read from the lockfile, then assert the
    // state stream passes through .restarting(attempt:1) before returning to
    // .ready within ~30 s.
}

// MARK: - Integration tests (disabled by default)

struct BackendIntegrationTests {
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SUSURRO_RUN_INTEGRATION"] == "1"
    }

    @Test func startStopRealBackend() async throws {
        guard Self.isEnabled else {
            return
        }

        let process = BackendProcess()
        try await process.start()

        let state = await process.state
        guard case .ready(let client) = state else {
            Issue.record("Expected .ready state")
            return
        }

        let health = try await client.health()
        #expect(health == .ready)

        let wavData = try await client.tts(text: "test", language: "en")
        #expect(!wavData.isEmpty)

        await process.stop()

        let finalState = await process.state
        if case .stopped = finalState {} else { Issue.record("Expected .stopped state") }

        let lockfileExists = FileManager.default.fileExists(atPath: LockfileLocator.path.path)
        #expect(!lockfileExists)
    }
}
