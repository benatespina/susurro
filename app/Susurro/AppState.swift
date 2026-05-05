import Observation

@MainActor @Observable
final class AppState {
    enum BackendStatus: Equatable {
        case starting, ready
    }
    enum AccessibilityStatus { case unknown, denied, granted }
    var backendStatus: BackendStatus = .starting
    var accessibilityStatus: AccessibilityStatus = .unknown
    var isPlaying: Bool = false
    var isPaused: Bool = false
    var hasResumableSession: Bool = false
}
