import AppKit
import SwiftUI

struct PanelContent: View {
    @Bindable var appState: AppState
    let onRead: () -> Void
    let onStop: () -> Void

    var body: some View {
        SelectionToolbar(
            appState: appState,
            onRead: onRead,
            onStop: onStop
        )
    }
}
