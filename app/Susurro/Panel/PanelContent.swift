import AppKit
import SwiftUI

struct PanelContent: View {
    @Bindable var appState: AppState
    @State private var pressed = false
    let onRead: () -> Void
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.clear
            playButton
                .scaleEffect(pressed ? 0.94 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playButton: some View {
        Button(action: handleTap) {
            HStack(spacing: 6) {
                Image(systemName: appState.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                Text(appState.isPlaying ? "Stop" : "Read")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 10)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .shadow(color: Color.accentColor.opacity(0.45), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private func handleTap() {
        if appState.isPlaying { onStop() } else { onRead() }
    }
}
