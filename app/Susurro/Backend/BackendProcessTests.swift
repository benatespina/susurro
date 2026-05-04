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

// MARK: - BackendClient (Phase 8 deletes these tests entirely)
// NOTE: BackendClient is now an in-process actor; HTTP-mocking tests removed.
// The BackendProcess.State unit tests below remain valid until Phase 8.

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
        guard case .ready = state else {
            Issue.record("Expected .ready state")
            return
        }

        await process.stop()

        let finalState = await process.state
        if case .stopped = finalState {} else { Issue.record("Expected .stopped state") }

        let lockfileExists = FileManager.default.fileExists(atPath: LockfileLocator.path.path)
        #expect(!lockfileExists)
    }
}
