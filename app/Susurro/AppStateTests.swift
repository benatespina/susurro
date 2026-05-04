import Testing
@testable import Susurro

@MainActor
struct AppStateTests {
    @Test func defaultStates() {
        let state = AppState()
        #expect(state.backendStatus == .starting)
        #expect(state.accessibilityStatus == .unknown)
        #expect(state.isPlaying == false)
    }

    @Test func backendStatusMutation() {
        let state = AppState()
        state.backendStatus = .ready
        #expect(state.backendStatus == .ready)
    }

    @Test func backendStatusStarting() {
        let state = AppState()
        state.backendStatus = .starting
        #expect(state.backendStatus == .starting)
    }
}
