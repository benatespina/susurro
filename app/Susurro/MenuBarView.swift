import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    let backend: BackendProcess
    let onStop: () -> Void
    let onRestartBackend: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            backendStatusRow
            accessibilityStatusRow
            playbackRow
            Divider()
            DiagnosticsMenu(state: appState, onRestartBackend: onRestartBackend)
            Divider()
            Button("Quit Susurro") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder
    private var playbackRow: some View {
        if appState.isPlaying {
            HStack(spacing: 4) {
                Text("Playing…")
                Button("Stop", action: onStop)
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var backendStatusRow: some View {
        switch appState.backendStatus {
        case .unknown:
            Text("Backend: stopped")
        case .starting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Backend: starting")
            }
        case .ready:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Backend: ready")
            }
        case .restarting(let attempt):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Backend: restarting (\(attempt)/3)…")
            }
        case .crashed:
            HStack(spacing: 4) {
                Text("Backend: crashed")
                Button("Restart") {
                    Task { try? await backend.start() }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var accessibilityStatusRow: some View {
        switch appState.accessibilityStatus {
        case .unknown:
            Text("Accessibility: checking…")
        case .denied:
            HStack(spacing: 4) {
                Text("Accessibility: denied")
                Button("Open Accessibility Settings…", action: AccessibilityPermission.openSystemSettings)
                    .buttonStyle(.borderless)
            }
        case .granted:
            Text("Accessibility: ✓ granted")
        }
    }
}
