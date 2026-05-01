// Susurro — Menu bar icon view with dynamic SF Symbol effects

import SwiftUI

struct MenuBarIcon: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Image(systemName: appState.iconState.systemImageName)
            .symbolEffect(.variableColor.iterative, isActive: appState.iconState.animatesVariableColor)
            .symbolEffect(.pulse, isActive: appState.iconState.animatesPulse)
    }
}
