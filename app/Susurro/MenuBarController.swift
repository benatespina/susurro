import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onShowTranscript: () -> Void = {}
    var onResumeReading: () -> Void = {}
    var onReadThis: () -> Void = {}
    var onRestartBackend: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}

    private let appState: AppState
    private let settings: TTSSettings
    private let backend: BackendProcess

    private let statusItem: NSStatusItem
    private let speakerImageView: NSImageView
    private let pauseButton: NSButton
    private let stopButton: NSButton
    private let menu = NSMenu()

    private static let slotSize: CGFloat = 22

    init(appState: AppState, settings: TTSSettings, backend: BackendProcess) {
        self.appState = appState
        self.settings = settings
        self.backend = backend
        statusItem = NSStatusBar.system.statusItem(withLength: Self.slotSize)
        speakerImageView = NSImageView()
        pauseButton = NSButton()
        stopButton = NSButton()
        super.init()

        configureSubButtons()
        menu.delegate = self
        applyPlaybackVisibility(isPlaying: false, isPaused: false)
    }

    func updatePlayback(isPlaying: Bool, isPaused: Bool) {
        applyPlaybackVisibility(isPlaying: isPlaying, isPaused: isPaused)
    }

    private func configureSubButtons() {
        guard let host = statusItem.button else { return }

        speakerImageView.frame = NSRect(x: 0, y: 0, width: Self.slotSize, height: Self.slotSize)
        speakerImageView.imageScaling = .scaleProportionallyDown
        speakerImageView.imageAlignment = .alignCenter
        speakerImageView.image = SusurroIcon.template()
        speakerImageView.toolTip = "Susurro"
        speakerImageView.wantsLayer = true
        let click = NSClickGestureRecognizer(target: self, action: #selector(speakerClicked(_:)))
        speakerImageView.addGestureRecognizer(click)
        host.addSubview(speakerImageView)

        configure(
            pauseButton,
            symbol: "pause.fill",
            label: "Pause",
            x: Self.slotSize,
            action: #selector(togglePauseClicked(_:))
        )
        pauseButton.isHidden = true
        host.addSubview(pauseButton)

        configure(
            stopButton,
            symbol: "stop.fill",
            label: "Stop",
            x: Self.slotSize * 2,
            action: #selector(stopClicked(_:))
        )
        stopButton.isHidden = true
        host.addSubview(stopButton)
    }

    private func configure(_ button: NSButton, symbol: String, label: String, x: CGFloat, action: Selector) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.frame = NSRect(x: x, y: 0, width: Self.slotSize, height: Self.slotSize)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.target = self
        button.action = action
    }

    private func applyPlaybackVisibility(isPlaying: Bool, isPaused: Bool) {
        let active = isPlaying || isPaused
        pauseButton.isHidden = !active
        stopButton.isHidden = !active
        let symbol = isPaused ? "play.fill" : "pause.fill"
        let label = isPaused ? "Resume" : "Pause"
        pauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        pauseButton.toolTip = label
        statusItem.length = active ? Self.slotSize * 3 : Self.slotSize
        applySpeakerState(isPlaying: isPlaying, isPaused: isPaused)
    }

    private func applySpeakerState(isPlaying: Bool, isPaused: Bool) {
        speakerImageView.layer?.removeAnimation(forKey: "susurro.pulse")

        if isPlaying {
            speakerImageView.layer?.opacity = 1.0
            startSpeakerPulse()
        } else if isPaused {
            speakerImageView.layer?.opacity = 0.55
        } else {
            speakerImageView.layer?.opacity = 1.0
        }
    }

    private func startSpeakerPulse() {
        guard let layer = speakerImageView.layer else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 0.85
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "susurro.pulse")
    }

    @objc private func speakerClicked(_ sender: Any?) {
        rebuildMenu()
        guard let host = statusItem.button else { return }
        let origin = NSPoint(x: 0, y: host.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: host)
    }

    @objc private func togglePauseClicked(_ sender: Any?) {
        onTogglePause()
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        addBackendStatus()
        addAccessibilityStatus()
        menu.addItem(.separator())

        if appState.hasResumableSession && !appState.isPlaying && !appState.isPaused {
            menu.addItem(menuItem(title: "Resume reading…", action: #selector(handleResume)))
        }
        let readItem = menuItem(title: "Read this (⌥⌘R)", action: #selector(handleReadThis))
        readItem.isEnabled = appState.backendStatus == .ready
        menu.addItem(readItem)
        menu.addItem(menuItem(title: "Show transcript…", action: #selector(handleShowTranscript)))

        menu.addItem(buildTTSMenu())
        menu.addItem(buildDiagnosticsMenu())
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Susurro", action: #selector(handleQuit)))
    }

    private func addBackendStatus() {
        switch appState.backendStatus {
        case .unknown:
            menu.addItem(disabledItem(title: "Backend: stopped"))
        case .starting:
            menu.addItem(disabledItem(title: "Backend: starting…"))
        case .ready:
            menu.addItem(disabledItem(title: "Backend: ready"))
        case .restarting(let attempt):
            menu.addItem(disabledItem(title: "Backend: restarting (\(attempt)/3)…"))
        case .crashed:
            menu.addItem(disabledItem(title: "Backend: crashed"))
            menu.addItem(menuItem(title: "Restart backend", action: #selector(handleRestartCrashedBackend)))
        }
    }

    private func addAccessibilityStatus() {
        switch appState.accessibilityStatus {
        case .unknown:
            menu.addItem(disabledItem(title: "Accessibility: checking…"))
        case .denied:
            menu.addItem(disabledItem(title: "Accessibility: denied"))
            menu.addItem(menuItem(title: "Open Accessibility Settings…", action: #selector(handleOpenAccessibility)))
        case .granted:
            menu.addItem(disabledItem(title: "Accessibility: ✓ granted"))
        }
    }

    private func buildTTSMenu() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "TTS Provider: \(settings.provider.displayName)", action: nil, keyEquivalent: ""
        )
        let sub = NSMenu()
        for p in TTSProvider.allCases {
            let item = NSMenuItem(
                title: p.displayName,
                action: #selector(handleSelectProvider(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = p.rawValue
            item.state = (settings.provider == p) ? .on : .off
            sub.addItem(item)
        }
        sub.addItem(.separator())
        sub.addItem(menuItem(title: "Configure Azure…", action: #selector(handleConfigureAzure)))
        sub.addItem(menuItem(title: "Pronunciations…", action: #selector(handleOpenPronunciations)))
        parent.submenu = sub
        return parent
    }

    private func buildDiagnosticsMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(menuItem(title: "Show Backend Logs", action: #selector(handleShowBackendLogs)))
        sub.addItem(menuItem(title: "Reveal Lockfile in Finder", action: #selector(handleRevealLockfile)))
        sub.addItem(menuItem(title: "Restart Backend", action: #selector(handleRestartBackendFromDiagnostics)))
        sub.addItem(.separator())
        sub.addItem(menuItem(title: "Copy Diagnostics to Clipboard", action: #selector(handleCopyDiagnostics)))
        parent.submenu = sub
        return parent
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func handleResume() { onResumeReading() }
    @objc private func handleReadThis() { onReadThis() }
    @objc private func handleShowTranscript() { onShowTranscript() }
    @objc private func handleQuit() { NSApp.terminate(nil) }
    @objc private func handleOpenAccessibility() { AccessibilityPermission.openSystemSettings() }
    @objc private func handleRestartCrashedBackend() {
        Task { try? await backend.start() }
    }
    @objc private func handleRestartBackendFromDiagnostics() { onRestartBackend() }

    @objc private func handleSelectProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = TTSProvider(rawValue: raw) else { return }
        if provider == .azure && !settings.azureConfigured {
            TTSConfigWindowController.show(settings: settings) { [weak self] in
                self?.settings.provider = .azure
                self?.onRestartBackend()
            }
        } else {
            settings.provider = provider
            onRestartBackend()
        }
    }

    @objc private func handleConfigureAzure() {
        TTSConfigWindowController.show(settings: settings) { [weak self] in
            guard let self else { return }
            if self.settings.provider == .azure { self.onRestartBackend() }
        }
    }

    @objc private func handleOpenPronunciations() {
        PronunciationsWindowController.show(backend: backend, settings: settings)
    }

    @objc private func handleShowBackendLogs() {
        NSWorkspace.shared.open(URL(filePath: "/System/Applications/Utilities/Console.app"))
    }

    @objc private func handleRevealLockfile() {
        let lockfileURL = LockfileLocator.path
        if FileManager.default.fileExists(atPath: lockfileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lockfileURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([lockfileURL.deletingLastPathComponent()])
        }
    }

    @objc private func handleCopyDiagnostics() {
        let state = appState
        Task { @MainActor in
            let report = await Diagnostics.collect(state: state)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.formatted, forType: .string)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}
