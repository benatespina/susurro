import SwiftUI
import UserNotifications

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    let backend: BackendProcess
    let settings: TTSSettings
    let playbackBridge: MenuBarPlaybackBridge?
    let onStop: () -> Void
    let onRestartBackend: () -> Void
    let onShowTranscript: () -> Void
    let onResumeReading: () -> Void
    let onReadThis: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onPlayPause: () -> Void

    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading) {
            backendStatusRow
            accessibilityStatusRow
            notificationsStatusRow
            playbackRow
            Divider()
            if appState.hasResumableSession && !appState.isPlaying {
                Button("Resume reading…", action: onResumeReading)
            }
            Button("Read this (⌥⌘R)", action: onReadThis)
                .disabled(appState.backendStatus != .ready)
            if appState.iconState != .playing && appState.iconState != .paused {
                Button("Show transcript…", action: onShowTranscript)
            }
            TTSMenu(settings: settings, backend: backend, onApply: onRestartBackend)
            DiagnosticsMenu(state: appState, onRestartBackend: onRestartBackend)
            Divider()
            Button("Quit Susurro") { NSApp.terminate(nil) }
        }
        .task {
            notificationAuthStatus = await SusurroNotifier.authorizationStatus()
        }
    }

    @ViewBuilder
    private var playbackRow: some View {
        if appState.iconState == .playing || appState.iconState == .paused,
           let bridge = playbackBridge {
            PlaybackHubView(
                bridge: bridge,
                onPrev: onPrev,
                onNext: onNext,
                onPlayPause: onPlayPause,
                onStop: onStop,
                onShowTranscript: onShowTranscript
            )
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

    @ViewBuilder
    private var notificationsStatusRow: some View {
        if notificationAuthStatus == .denied {
            HStack(spacing: 4) {
                Text("Notifications: denied")
                Button("Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
