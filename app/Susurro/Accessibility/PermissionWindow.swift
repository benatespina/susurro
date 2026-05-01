import AppKit
import SwiftUI

@MainActor
final class PermissionWindow {
    private let window: NSWindow
    private let onCheck: () -> Void

    init(onCheck: @escaping () -> Void) {
        self.onCheck = onCheck
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Susurro"
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PermissionWindowContent(
                onOpenSettings: AccessibilityPermission.openSystemSettings,
                onRecheck: onCheck
            )
        )
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }
}

private struct PermissionWindowContent: View {
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Susurro needs Accessibility access")
                .font(.title2)
                .bold()
            Text(
                "To read text from any app, Susurro needs permission to detect text selection. " +
                "Open System Settings → Privacy & Security → Accessibility, find Susurro in the list, " +
                "and toggle it on. After enabling it, click 'Re-check' below. " +
                "If the toggle doesn't take effect immediately, restart Susurro."
            )
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings", action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
                Button("I granted it — Re-check", action: onRecheck)
            }
        }
        .padding(24)
        .frame(width: 480, height: 320)
    }
}
