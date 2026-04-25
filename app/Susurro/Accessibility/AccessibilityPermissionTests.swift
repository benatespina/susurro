import Testing
@testable import Susurro

@MainActor
struct AccessibilityPermissionTests {
    @Test func isGrantedReturnsBool() {
        _ = AccessibilityPermission.isGranted()
    }

    @Test func appStateTransitions() {
        let state = AppState()
        #expect(state.accessibilityStatus == .unknown)
        state.accessibilityStatus = .denied
        #expect(state.accessibilityStatus == .denied)
        state.accessibilityStatus = .granted
        #expect(state.accessibilityStatus == .granted)
    }
}
