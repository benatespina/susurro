import ApplicationServices
import AppKit

@MainActor
final class SelectionObserver {
    enum Event: Sendable { case changed, cleared }

    private var currentObserver: AXObserver?
    private var currentPid: pid_t?
    // nonisolated(unsafe) so deinit can access it without crossing actor boundary.
    // It is always written from @MainActor init and read only in deinit (after all strong refs drop).
    nonisolated(unsafe) private var workspaceObserverToken: AnyObject?
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var lastEmit: ContinuousClock.Instant?
    private static let minimumEmitInterval: Duration = .milliseconds(50)

    init() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Extract pid synchronously before any Task hop — Notification is not Sendable
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, let pid else { return }
                self.rebuild(forPid: pid)
            }
        }
        workspaceObserverToken = token as AnyObject
        if let app = NSWorkspace.shared.frontmostApplication {
            rebuild(forPid: app.processIdentifier)
        }
    }

    deinit {
        // workspaceObserverToken is AnyObject (not actor-isolated), safe from nonisolated deinit
        if let token = workspaceObserverToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    func events() -> AsyncStream<Event> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            Task { @MainActor [weak self] in
                self?.continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    fileprivate func emit(_ event: Event) {
        let now = ContinuousClock.now
        if let last = lastEmit, now - last < Self.minimumEmitInterval {
            return
        }
        lastEmit = now
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func rebuild(forPid pid: pid_t) {
        teardownCurrent()
        currentPid = pid
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        let appElement = AXUIElementCreateApplication(pid)
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return }
        currentObserver = observer

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXSelectedTextChangedNotification as CFString, refcon)

        if let focusedWindow = focusedWindowElement(forAppElement: appElement) {
            AXObserverAddNotification(
                observer,
                focusedWindow,
                kAXSelectedTextChangedNotification as CFString,
                refcon
            )
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func focusedWindowElement(forAppElement appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref
        else { return nil }
        return (ref as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private func teardownCurrent() {
        guard let observer = currentObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        currentObserver = nil
    }
}

private func axCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let observerSelf = Unmanaged<SelectionObserver>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in observerSelf.emit(.changed) }
}
