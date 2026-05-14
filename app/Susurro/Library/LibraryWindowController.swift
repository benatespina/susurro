import AppKit
import SwiftUI

@MainActor
enum LibraryWindowController {
    private static var windowController: NSWindowController?

    static func show(store: LibraryStore, synthesizer: LibrarySynthesizer, state: LibrarySynthesisState) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LibraryView(
            store: store,
            synthesizer: synthesizer,
            synthesisState: state,
            onSynthesize: { itemID in
                Task { await synthesizer.enqueue(itemID: itemID) }
            }
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
