import Testing
@testable import Susurro

@MainActor
struct AppStateTests {
    @Test func defaultStates() {
        let state = AppState()
        #expect(state.backendStatus == .unknown)
        #expect(state.accessibilityStatus == .unknown)
        #expect(state.isPlaying == false)
    }

    @Test func backendStatusMutation() {
        let state = AppState()
        state.backendStatus = .ready
        #expect(state.backendStatus == .ready)
    }

    @Test func updateFromRestartingSetsAttempt() {
        let state = AppState()
        state.update(from: .restarting(attempt: 2))
        #expect(state.backendStatus == .restarting(attempt: 2))
    }

    @Test func updateFromReadyAfterRestarting() {
        let state = AppState()
        state.update(from: .restarting(attempt: 2))
        state.update(from: .ready(BackendClient(lockfile: Lockfile(port: 9999, pid: 1, token: "t", startedAt: "2026-01-01T00:00:00Z"))))
        #expect(state.backendStatus == .ready)
    }

    @Test func restartingAttemptEquatableDistinction() {
        #expect(AppState.BackendStatus.restarting(attempt: 1) != AppState.BackendStatus.restarting(attempt: 2))
    }
}
