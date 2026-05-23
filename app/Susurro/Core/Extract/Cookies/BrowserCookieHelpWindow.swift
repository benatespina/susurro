import Foundation
import AppKit
import SwiftUI

@MainActor
final class BrowserCookieHelpWindow {
    private let window: NSWindow
    private let error: BrowserCookieError

    init(error: BrowserCookieError) {
        self.error = error
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 320)
        self.window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Susurro · X Article access"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.contentView = NSHostingView(rootView: BrowserCookieHelpContent(error: error) { [weak self] in
            self?.close()
        })
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.orderOut(nil)
    }
}

struct BrowserCookieHelpContent: View {
    let error: BrowserCookieError
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Susurro needs access to your browser's cookies")
                .font(.headline)
            Text(message(for: error))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Spacer()
                Button("Got it", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 320)
    }

    private func message(for error: BrowserCookieError) -> String {
        switch error {
        case .onlySafariDetected:
            return "To extract the full body of X articles, Susurro reads session cookies from a Chromium-based browser (Chrome, Arc, Brave, or Microsoft Edge). You're using Safari as your default browser, and none of those browsers are installed. Install one and sign in to x.com to enable full-article extraction."
        case .noBrowserDetected:
            return "Susurro could not detect a supported browser with an active x.com session. Sign in to x.com in Chrome, Arc, Brave, or Microsoft Edge to enable full-article extraction."
        case .keychainDenied(let source):
            return "Susurro could not access \(source.displayName)'s saved encryption key. macOS asked you to allow access — choose Allow (or Always Allow) when the prompt appears. Without this, only the article preview can be extracted."
        case .noXSessionCookies(let source):
            return "No x.com session was found in \(source.displayName) (or any other supported browser). Sign in to x.com in your browser to enable full-article extraction."
        case .databaseUnavailable, .keychainNotFound, .decryptionFailed:
            // Should not surface — guarded in notifier
            return "Susurro encountered an internal issue accessing browser cookies. Only the article preview will be extracted."
        }
    }
}
