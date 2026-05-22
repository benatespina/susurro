import Foundation
import AppKit

@MainActor
final class BrowserCookieErrorNotifier {
    private(set) var hasShownThisSession = false
    private var window: BrowserCookieHelpWindow?

    func notify(_ error: BrowserCookieError) {
        // Only surface actionable errors. Non-actionable ones (.decryptionFailed,
        // .databaseUnavailable, .keychainNotFound) are silent — they're either internal
        // schema issues or transient — the user can't do anything about them.
        switch error {
        case .onlySafariDetected, .noBrowserDetected, .keychainDenied, .noXSessionCookies:
            break
        case .databaseUnavailable, .keychainNotFound, .decryptionFailed:
            return
        }

        guard !hasShownThisSession else { return }
        hasShownThisSession = true

        let helpWindow = BrowserCookieHelpWindow(error: error)
        helpWindow.show()
        self.window = helpWindow
    }

    /// Test helper to reset session state.
    func resetForTesting() {
        hasShownThisSession = false
        window?.close()
        window = nil
    }
}
