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

    var profilesRootDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .chrome: return home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        case .arc:    return home.appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)
        case .brave:  return home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true)
        case .edge:   return home.appendingPathComponent("Library/Application Support/Microsoft Edge", isDirectory: true)
        }
    }

    var cookiesDatabasePath: URL {
        profilesRootDirectory.appendingPathComponent("Default/Cookies")
    }

    func cookiesDatabasePaths() -> [URL] {
        let fm = FileManager.default
        let root = profilesRootDirectory
        var paths: [URL] = []
        let defaultPath = root.appendingPathComponent("Default/Cookies")
        if fm.fileExists(atPath: defaultPath.path) {
            paths.append(defaultPath)
        }
        if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let profileDirs = entries
                .filter { $0.lastPathComponent.hasPrefix("Profile ") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for dir in profileDirs {
                let cookies = dir.appendingPathComponent("Cookies")
                if fm.fileExists(atPath: cookies.path) {
                    paths.append(cookies)
                }
            }
        }
        return paths
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
