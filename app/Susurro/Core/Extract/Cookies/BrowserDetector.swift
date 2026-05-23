import Foundation
import AppKit

struct BrowserDetector {
    /// Optional Safari bundle ID we detect specifically to surface a clearer error.
    static let safariBundleIdentifier = "com.apple.Safari"

    /// Bundle-ID -> BrowserSource mapping (pure function for tests).
    static func source(forBundleIdentifier bundleID: String) -> BrowserSource? {
        BrowserSource.allCases.first { $0.bundleIdentifier == bundleID }
    }

    /// System default browser. nil if unresolved or not one of our known browsers/Safari.
    /// Returns:
    ///   - a `BrowserSource` if the default is one of the supported Chromium variants
    ///   - nil if the default is Safari (use `isSafariDefault()` to disambiguate) or anything else
    static func defaultBrowser() -> BrowserSource? {
        guard let bundleID = defaultBrowserBundleIdentifier() else { return nil }
        return source(forBundleIdentifier: bundleID)
    }

    /// True if the system default browser is Safari.
    static func isSafariDefault() -> Bool {
        defaultBrowserBundleIdentifier() == safariBundleIdentifier
    }

    /// Subset of `BrowserSource.allCases` that have at least one profile with a Cookies file.
    static func installedBrowsers() -> [BrowserSource] {
        BrowserSource.allCases.filter { !$0.cookiesDatabasePaths().isEmpty }
    }

    /// True iff Safari is the system default browser AND no Chromium variant is installed.
    static func isSafariOnly() -> Bool {
        isSafariDefault() && installedBrowsers().isEmpty
    }

    // MARK: - Private

    private static func defaultBrowserBundleIdentifier() -> String? {
        guard let url = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }
}
