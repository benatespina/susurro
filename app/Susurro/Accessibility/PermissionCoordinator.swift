import AppKit

@MainActor
final class PermissionCoordinator {
    private let appState: AppState
    private var window: PermissionWindow?
    private var pollTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        check()
        workspaceObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.check()
            }
        }
    }

    func tearDown() {
        if let observer = workspaceObserver {
            NotificationCenter.default.removeObserver(observer)
            workspaceObserver = nil
        }
        pollTask?.cancel()
        pollTask = nil
    }

    func check() {
        let granted = AccessibilityPermission.isGranted()
        appState.accessibilityStatus = granted ? .granted : .denied
        if granted {
            window?.close()
            window = nil
            pollTask?.cancel()
            pollTask = nil
        } else {
            ensureWindowShown()
        }
    }

    private func ensureWindowShown() {
        if window == nil {
            let win = PermissionWindow(onCheck: { [weak self] in
                Task { @MainActor [weak self] in self?.check() }
            })
            win.show()
            window = win
            _ = AccessibilityPermission.requestPrompt()
        }
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if AccessibilityPermission.isGranted() {
                    self.check()
                    return
                }
            }
        }
    }
}
