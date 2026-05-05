import AppKit
import SwiftUI

@MainActor
enum TTSConfigWindowController {
    private static var windowController: NSWindowController?

    static func show(settings: TTSSettings, onSave: @escaping () -> Void) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = TTSConfigView(settings: settings) {
            onSave()
            close()
        }
        let hosting = NSHostingController(rootView: view)
        hosting.preferredContentSize = NSSize(width: 420, height: 270)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Configure Azure Speech"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 270))
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

private struct TTSConfigView: View {
    @Bindable var settings: TTSSettings
    @State private var azureKey: String = ""
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use pricing tier F0 to stay within 500K chars/month free.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                SecureField("Subscription Key", text: $azureKey)
                TextField("Region (e.g. westeurope)", text: $settings.azureRegion)
            }

            HStack {
                Spacer()
                Button("Cancel") { TTSConfigWindowController.close() }
                Button("Save") {
                    settings.azureKey = azureKey
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(azureKey.isEmpty || settings.azureRegion.isEmpty)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Translate to Spanish before reading", isOn: $settings.translateToSpanish)
                Text("When enabled, non-Spanish text is translated to Spanish on-device before being read aloud. Spanish text is read directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420, height: 270)
        .onAppear { azureKey = settings.azureKey }
    }
}
