import SwiftUI

private struct ToolbarSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct SelectionToolbar: View {
    @Bindable var appState: AppState
    let onRead: () -> Void
    let onStop: () -> Void
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        circleContent
            .padding(8)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ToolbarSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(ToolbarSizeKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                onSizeChange(size)
            }
    }

    func invokeAction() {
        if appState.isPlaying { onStop() } else { onRead() }
    }

    private var circleContent: some View {
        ToolbarButton(
            systemImage: appState.isPlaying ? "stop.fill" : "waveform",
            isPrimary: true,
            action: invokeAction
        )
        .padding(4)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Circle())
        )
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}
