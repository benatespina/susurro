import AppKit
import SwiftUI

struct PanelContent: View {
    @Bindable var appState: AppState
    let selectedText: String
    let onRead: () -> Void
    let onStop: () -> Void
    let onTeachPronunciation: (String) -> Void
    let onDismiss: () -> Void
    let onSpeedDown: () -> Void
    let onSpeedUp: () -> Void
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        SelectionToolbar(
            appState: appState,
            selectedText: selectedText,
            onRead: onRead,
            onStop: onStop,
            onTeachPronunciation: onTeachPronunciation,
            onDismiss: onDismiss,
            onSpeedDown: onSpeedDown,
            onSpeedUp: onSpeedUp,
            onSizeChange: onSizeChange
        )
    }
}
