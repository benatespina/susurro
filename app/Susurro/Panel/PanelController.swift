import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let observer: SelectionObserver
    private let appState: AppState
    private var panel: FloatingPanel?
    private var observationTask: Task<Void, Never>?
    private var lastSelectionText: String?
    var onRead: ((String) -> Void)?
    var onStop: (() -> Void)?

    init(observer: SelectionObserver, appState: AppState) {
        self.observer = observer
        self.appState = appState
        startObserving()
        installGlobalMouseAndKeyMonitor()
    }

    deinit {
        observationTask?.cancel()
    }

    private func startObserving() {
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.observer.events() {
                switch event {
                case .changed: self.handleSelectionChanged()
                case .cleared: self.hide()
                }
            }
        }
    }

    private func installGlobalMouseAndKeyMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.hide()
                    return
                }
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    guard let panel = self.panel, panel.isVisible else { return }
                    let mouse = NSEvent.mouseLocation
                    if !panel.frame.contains(mouse) {
                        self.hide()
                    }
                }
            }
        }
    }

    private func handleSelectionChanged() {
        guard let selection = SelectionReader.current() else {
            hide()
            return
        }
        lastSelectionText = selection.text

        let panelSize = CGSize(width: 80, height: 60)
        let screen = screenForSelection(bounds: selection.bounds)
        let position: CGPoint
        if let bounds = selection.bounds {
            position = PanelPositioner.position(for: bounds, panelSize: panelSize, on: screen)
        } else {
            position = PanelPositioner.positionNearMouse(panelSize: panelSize, on: screen)
        }
        showPanel(at: position, size: panelSize)
    }

    private func screenForSelection(bounds: CGRect?) -> NSScreen {
        guard let bounds, let screen = NSScreen.screens.first(where: { $0.frame.intersects(bounds) }) else {
            return NSScreen.main ?? NSScreen.screens[0]
        }
        return screen
    }

    private func showPanel(at point: CGPoint, size: CGSize) {
        let content = PanelContent(
            appState: appState,
            onRead: { [weak self] in
                guard let text = self?.lastSelectionText ?? SelectionReader.current()?.text else { return }
                self?.onRead?(text)
            },
            onStop: { [weak self] in self?.onStop?() }
        )
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)

        if let panel {
            panel.contentView = host
        } else {
            panel = FloatingPanel(content: host)
        }

        panel?.setFrameOrigin(point)
        panel?.setContentSize(size)
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }
}
