import SwiftUI

struct SelectionToolbar: View {
    @Bindable var appState: AppState
    let onRead: () -> Void
    let onStop: () -> Void

    var body: some View {
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
        .padding(4)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Circle())
        )
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        .padding(8)
    }

    func invokeAction() {
        if appState.isPlaying { onStop() } else { onRead() }
    }
}
