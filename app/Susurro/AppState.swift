import Observation

@MainActor @Observable
final class AppState {
    enum BackendStatus { case unknown, starting, ready, crashed }
    enum AccessibilityStatus { case unknown, denied, granted }
    var backendStatus: BackendStatus = .unknown
    var accessibilityStatus: AccessibilityStatus = .unknown
    var isPlaying: Bool = false
}
