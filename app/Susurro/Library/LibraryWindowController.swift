import AppKit
import SwiftUI

// Groups all Library-window dependencies to keep call sites clean.
struct LibraryEnvironment {
    var store: LibraryStore
    var synthesizer: LibrarySynthesizer
    var synthesisState: LibrarySynthesisState
    var publisher: (any LibraryPublishing)?
    var player: LibraryPlayer
    var settings: LibrarySettings
    var onMarkPlayed: (UUID) -> Void
    var onDelete: ((UUID) -> Void)?
}

@MainActor
enum LibraryWindowController {
    private static var windowController: NSWindowController?

    static func show(environment: LibraryEnvironment) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let env = environment
        let view = LibraryView(
            store: env.store,
            synthesizer: env.synthesizer,
            synthesisState: env.synthesisState,
            publisher: env.publisher,
            player: env.player,
            settings: env.settings,
            onSynthesize: { itemID in
                Task { await env.synthesizer.enqueue(itemID: itemID) }
            },
            onMarkPlayed: env.onMarkPlayed,
            onDelete: env.onDelete
        )
        let hosting = NSHostingController(rootView: view)
        hosting.preferredContentSize = NSSize(width: 720, height: 480)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Reading List"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 480))
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        windowController?.close()
        windowController = nil
    }
}
