import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading) {
            Text("Backend: \(backendLabel)")
            Text("Accessibility: \(accessibilityLabel)")
            Text("Playing: \(appState.isPlaying ? "yes" : "no")")
            Divider()
            Button("Quit Susurro") { NSApp.terminate(nil) }
        }
    }

    private var backendLabel: String {
        switch appState.backendStatus {
        case .unknown: "unknown"
        case .starting: "starting"
        case .ready: "ready"
        case .crashed: "crashed"
        }
    }

    private var accessibilityLabel: String {
        switch appState.accessibilityStatus {
        case .unknown: "unknown"
        case .denied: "denied"
        case .granted: "granted"
        }
    }
}
