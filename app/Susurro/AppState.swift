import Foundation
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
    var iconState: IconState = .idle
    var extractionStartedAt: Date?
    var isPaused: Bool = false

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

    func recomputeIcon() {
        // Transient states set explicitly by readFromCurrentApp — leave them
        // in place until the caller clears them (or the 4-second reset fires).
        switch iconState {
        case .extracting, .loading, .error:
            return
        default:
            break
        }

        let newState: IconState
        if isPlaying {
            newState = .playing
        } else if isPaused || hasResumableSession {
            newState = .paused
        } else {
            newState = .idle
        }
        guard newState != iconState else { return }
        iconState = newState
    }
}
