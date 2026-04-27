import AppKit
import SwiftUI

struct DiagnosticsMenu: View {
    var state: AppState
    let onRestartBackend: () -> Void

    var body: some View {
        Menu("Diagnostics") {
            Button("Show Backend Logs") { showBackendLogs() }
            Button("Reveal Lockfile in Finder") { revealLockfile() }
            Button("Restart Backend") { onRestartBackend() }
            Divider()
            Button("Copy Diagnostics to Clipboard") { copyDiagnostics() }
        }
    }

    private func showBackendLogs() {
        NSWorkspace.shared.open(URL(filePath: "/System/Applications/Utilities/Console.app"))
    }

    private func revealLockfile() {
        let lockfileURL = LockfileLocator.path
        if FileManager.default.fileExists(atPath: lockfileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lockfileURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([lockfileURL.deletingLastPathComponent()])
        }
    }

    private func copyDiagnostics() {
        Task { @MainActor in
            let report = await Diagnostics.collect(state: state)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.formatted, forType: .string)
        }
    }
}
