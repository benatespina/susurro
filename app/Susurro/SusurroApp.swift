import SwiftUI

@main struct SusurroApp: App {
    @State private var appState = AppState()

    init() {
        AppLogger.app.info("Susurro launched")
    }

    var body: some Scene {
        MenuBarExtra("Susurro", systemImage: "speaker.wave.2") {
            MenuBarView()
                .environment(appState)
        }
    }
}
