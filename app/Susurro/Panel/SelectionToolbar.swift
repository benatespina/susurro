import SwiftUI

private struct ToolbarSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct SelectionToolbar: View {
    @Bindable var appState: AppState
    let selectedText: String
    let onRead: () -> Void
    let onStop: () -> Void
    let onTeachPronunciation: (String) -> Void
    let onDismiss: () -> Void
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        pillContent
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

    private var pillContent: some View {
        HStack(spacing: 4) {
            ToolbarButton(
                systemImage: appState.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                action: { if appState.isPlaying { onStop() } else { onRead() } }
            )
            ToolbarButton(
                systemImage: "character.book.closed",
                action: { onTeachPronunciation(selectedText) }
            )
            ToolbarButton(
                systemImage: "xmark",
                action: onDismiss
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Capsule())
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}
