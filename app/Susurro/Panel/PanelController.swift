import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let observer: SelectionObserver
    private let appState: AppState
    private var panel: FloatingPanel?
    private var observationTask: Task<Void, Never>?
    private var lastSelectionText: String?
    private var lastSelectionRect: CGRect?
    var onRead: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onHide: (() -> Void)?

    private static let estimatedToolbarSize = CGSize(width: 60, height: 56)

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
                case .cleared, .rebuilding: self.hide()
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
        lastSelectionRect = selection.bounds

        let initialSize = Self.estimatedToolbarSize
        let screen = screenForSelection(bounds: selection.bounds)
        let position: CGPoint
        if let bounds = selection.bounds {
            position = PanelPositioner.position(for: bounds, panelSize: initialSize, on: screen)
        } else {
            position = PanelPositioner.positionNearMouse(panelSize: initialSize, on: screen)
        }
        showPanel(at: position, size: initialSize)
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
            onStop: { [weak self] in self?.onStop?() },
            onSizeChange: { [weak self] newSize in
                self?.handleContentSizeChange(newSize)
            }
        )
        if let panel, let host = panel.contentView as? NSHostingView<PanelContent> {
            host.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            host.frame = NSRect(origin: .zero, size: size)
            panel = FloatingPanel(content: host)
        }

        panel?.setFrameOrigin(point)
        panel?.setContentSize(size)
        panel?.orderFrontRegardless()
    }

    private func handleContentSizeChange(_ newSize: CGSize) {
        guard let panel else { return }
        let screen = screenForSelection(bounds: lastSelectionRect)
        let position: CGPoint
        if let rect = lastSelectionRect {
            position = PanelPositioner.position(for: rect, panelSize: newSize, on: screen)
        } else {
            position = PanelPositioner.positionNearMouse(panelSize: newSize, on: screen)
        }
        Task { @MainActor in
            panel.setContentSize(newSize)
            panel.setFrameOrigin(position)
        }
    }

    private func hide() {
        panel?.orderOut(nil)
        onHide?()
    }
}
