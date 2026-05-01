import Observation

@MainActor @Observable
final class AppState {
    enum BackendStatus: Equatable {
        case unknown, starting, ready, crashed
        case restarting(attempt: Int)
    }
    enum AccessibilityStatus { case unknown, denied, granted }
    var backendStatus: BackendStatus = .unknown
    var accessibilityStatus: AccessibilityStatus = .unknown
    var isPlaying: Bool = false
    var hasResumableSession: Bool = false

    func update(from backendState: BackendProcess.State) {
        switch backendState {
        case .stopped:
            backendStatus = .unknown
        case .starting:
            backendStatus = .starting
        case .ready:
            backendStatus = .ready
        case .restarting(let attempt):
            backendStatus = .restarting(attempt: attempt)
        case .crashed:
            backendStatus = .crashed
        }
    }
}
