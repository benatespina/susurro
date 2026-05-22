import Foundation

enum BrowserSource: String, CaseIterable, Sendable {
    case chrome
    case arc
    case brave
    case edge

    var displayName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave"
        case .edge: return "Microsoft Edge"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .arc: return "company.thebrowser.Browser"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        }
    }

    var cookiesDatabasePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support")
        switch self {
        case .chrome:
            return appSupport
                .appendingPathComponent("Google/Chrome/Default/Cookies")
        case .arc:
            return appSupport
                .appendingPathComponent("Arc/User Data/Default/Cookies")
        case .brave:
            return appSupport
                .appendingPathComponent("BraveSoftware/Brave-Browser/Default/Cookies")
        case .edge:
            return appSupport
                .appendingPathComponent("Microsoft Edge/Default/Cookies")
        }
    }

    var keychainService: String {
        switch self {
        case .chrome, .arc, .brave: return "Chrome Safe Storage"
        case .edge: return "Microsoft Edge Safe Storage"
        }
    }

    var keychainAccount: String {
        switch self {
        case .chrome, .arc, .brave: return "Chrome"
        case .edge: return "Microsoft Edge"
        }
    }
}
