// Susurro — Menu bar icon state enum with SF Symbol helpers

enum IconState: Equatable {
    case idle
    case extracting
    case loading
    case playing
    case paused
    case error

    var systemImageName: String {
        switch self {
        case .idle: return "speaker.wave.2"
        case .extracting: return "text.magnifyingglass"
        case .loading: return "arrow.triangle.2.circlepath"
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var animatesVariableColor: Bool {
        switch self {
        case .extracting, .loading: return true
        default: return false
        }
    }

    var animatesPulse: Bool {
        self == .playing
    }

    /// True while audio is actively playing or paused (i.e. a session is in progress).
    var isActivePlayback: Bool {
        self == .playing || self == .paused
    }
}
