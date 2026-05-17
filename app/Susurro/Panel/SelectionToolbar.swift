import SwiftUI

struct SelectionToolbar: View {
    @Bindable var appState: AppState
    let onRead: () -> Void
    let onStop: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Primary action: read / stop
            ToolbarButton(isPrimary: true, action: invokeAction) {
                if appState.isPlaying {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(nsImage: SusurroIcon.template())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
            }

            // Save to reading list
            ToolbarButton(isPrimary: false, action: onSave) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .accessibilityLabel("Save to Reading List")
            .help("Save to Reading List")
        }
        .padding(4)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Capsule())
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        .padding(8)
    }

    func invokeAction() {
        if appState.isPlaying { onStop() } else { onRead() }
    }
}
