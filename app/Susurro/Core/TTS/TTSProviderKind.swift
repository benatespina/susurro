import Foundation

enum TTSProviderKind: String, CaseIterable, Sendable {
    case edge
    case azure

    var displayName: String {
        switch self {
        case .edge: return "Microsoft Edge (free)"
        case .azure: return "Azure Speech (paid)"
        }
    }
}
