import SwiftUI

struct PanelContent: View {
    @Bindable var appState: AppState
    @State private var hovering = false
    @State private var pressed = false
    let onRead: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.95),
                                Color.accentColor.opacity(0.75),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 2)

                Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(x: appState.isPlaying ? 0 : 1)
            }
            .frame(width: 32, height: 32)
            .scaleEffect(pressed ? 0.92 : (hovering ? 1.08 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: hovering)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: pressed)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .padding(4)
        .onHover { hovering = $0 }
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
