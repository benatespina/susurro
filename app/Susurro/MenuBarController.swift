import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onShowTranscript: () -> Void = {}
    var onResumeReading: () -> Void = {}
    var onReadThis: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}
    var onSpeedDown: (() -> Void)?
    var onSpeedUp: (() -> Void)?

    private let appState: AppState
    private let settings: TTSSettings
    private let ipcServer: IPCServer

    private var cachedLastSeenCwd: String?

    private let statusItem: NSStatusItem
    private let speakerImageView: NSImageView
    private let pauseButton: NSButton
    private let stopButton: NSButton
    private let speedDownButton: NSButton
    private let speedLabel: NSTextField
    private let speedUpButton: NSButton
    private let menu = NSMenu()

    private var registryCancellables = Set<AnyCancellable>()

    private static let slotSize: CGFloat = 22
    private static let speedLabelWidth: CGFloat = 40

    init(appState: AppState, settings: TTSSettings, ipcServer: IPCServer) {
        self.appState = appState
        self.settings = settings
        self.ipcServer = ipcServer
        statusItem = NSStatusBar.system.statusItem(withLength: SusurroIcon.iconWidth)
        speakerImageView = NSImageView()
        pauseButton = NSButton()
        stopButton = NSButton()
        speedDownButton = NSButton()
        speedLabel = NSTextField()
        speedUpButton = NSButton()
        super.init()

        configureSubButtons()
        menu.delegate = self
        applyPlaybackVisibility(isPlaying: false, isPaused: false)

        // Observe registry readiness so the menu status reflects live-swap.
        TTSProviderRegistry.shared.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Menus are rebuilt on open; no persistent menu item to update here.
                _ = self
            }
            .store(in: &registryCancellables)
    }

    func updatePlayback(isPlaying: Bool, isPaused: Bool) {
        applyPlaybackVisibility(isPlaying: isPlaying, isPaused: isPaused)
    }

    private func configureSubButtons() {
        guard let host = statusItem.button else { return }

        speakerImageView.frame = NSRect(x: 0, y: 0, width: SusurroIcon.iconWidth, height: Self.slotSize)
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
            x: SusurroIcon.iconWidth,
            action: #selector(togglePauseClicked(_:))
        )
        pauseButton.isHidden = true
        host.addSubview(pauseButton)

        configure(
            stopButton,
            symbol: "stop.fill",
            label: "Stop",
            x: SusurroIcon.iconWidth + Self.slotSize,
            action: #selector(stopClicked(_:))
        )
        stopButton.isHidden = true
        host.addSubview(stopButton)

        configure(
            speedDownButton,
            symbol: "tortoise.fill",
            label: "Slow down",
            x: SusurroIcon.iconWidth + Self.slotSize * 2,
            action: #selector(speedDownClicked(_:))
        )
        speedDownButton.isHidden = true
        host.addSubview(speedDownButton)

        speedLabel.frame = NSRect(
            x: SusurroIcon.iconWidth + Self.slotSize * 3,
            y: 0,
            width: Self.speedLabelWidth,
            height: Self.slotSize
        )
        speedLabel.stringValue = PlaybackSpeed.formatted(PlaybackSpeed.default)
        speedLabel.isEditable = false
        speedLabel.isSelectable = false
        speedLabel.isBordered = false
        speedLabel.drawsBackground = false
        speedLabel.alignment = .center
        speedLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        speedLabel.isHidden = true
        host.addSubview(speedLabel)

        configure(
            speedUpButton,
            symbol: "hare.fill",
            label: "Speed up",
            x: SusurroIcon.iconWidth + Self.slotSize * 3 + Self.speedLabelWidth,
            action: #selector(speedUpClicked(_:))
        )
        speedUpButton.isHidden = true
        host.addSubview(speedUpButton)

        centerSubviewsVertically()
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

    /// Reframes every subview so its vertical center aligns with the host button's
    /// actual midpoint. Called after all subviews have been added.
    private func centerSubviewsVertically() {
        guard let host = statusItem.button else { return }
        let hostHeight = host.bounds.height > 0 ? host.bounds.height : Self.slotSize

        func centered(_ view: NSView) {
            var f = view.frame
            f.origin.y = (hostHeight - f.height).rounded() / 2
            view.frame = f
        }

        centered(speakerImageView)
        centered(pauseButton)
        centered(stopButton)
        centered(speedDownButton)
        centered(speedLabel)
        centered(speedUpButton)
    }

    private func applyPlaybackVisibility(isPlaying: Bool, isPaused: Bool) {
        let active = isPlaying || isPaused
        pauseButton.isHidden = !active
        stopButton.isHidden = !active
        speedDownButton.isHidden = !active
        speedLabel.isHidden = !active
        speedUpButton.isHidden = !active
        let symbol = isPaused ? "play.fill" : "pause.fill"
        let label = isPaused ? "Resume" : "Pause"
        pauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        pauseButton.toolTip = label
        statusItem.length = active
            ? SusurroIcon.iconWidth + Self.slotSize * 4 + Self.speedLabelWidth
            : SusurroIcon.iconWidth
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
        let server = ipcServer
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cachedLastSeenCwd = await server.lastSeenCwd
            self.rebuildMenu()
            guard let host = self.statusItem.button else { return }
            let origin = NSPoint(x: 0, y: host.bounds.height + 4)
            self.menu.popUp(positioning: nil, at: origin, in: host)
        }
    }

    @objc private func togglePauseClicked(_ sender: Any?) {
        onTogglePause()
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop()
    }

    @objc private func speedDownClicked(_ sender: Any?) {
        onSpeedDown?()
    }

    @objc private func speedUpClicked(_ sender: Any?) {
        onSpeedUp?()
    }

    func updateRate(_ rate: Float) {
        speedLabel.stringValue = PlaybackSpeed.formatted(rate)
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

        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesTriggered),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)
        menu.addItem(.separator())

        menu.addItem(buildTTSMenu())
        menu.addItem(buildClaudeIntegrationMenu())
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Susurro", action: #selector(handleQuit)))
    }

    private func addBackendStatus() {
        let registry = TTSProviderRegistry.shared
        if !registry.isReady {
            menu.addItem(disabledItem(title: "TTS: Loading…"))
        } else {
            switch appState.backendStatus {
            case .starting:
                menu.addItem(disabledItem(title: "TTS: Loading…"))
            case .ready:
                menu.addItem(disabledItem(title: "Ready — \(settings.provider.displayName)"))
            }
        }

        if registry.azureConfigurationRequired {
            menu.addItem(disabledItem(title: "⚠ Azure key/region required"))
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
        for p in TTSProviderKind.allCases {
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
        sub.addItem(.separator())
        let translateItem = NSMenuItem(
            title: "Translate to Spanish before reading",
            action: #selector(handleToggleTranslateToSpanish),
            keyEquivalent: ""
        )
        translateItem.target = self
        translateItem.state = settings.translateToSpanish ? .on : .off
        sub.addItem(translateItem)
        parent.submenu = sub
        return parent
    }

    private func buildClaudeIntegrationMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Claude Code Integration", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let cliInstalled = CLIInstaller.isInstalled()
        let cliItem = NSMenuItem(
            title: cliInstalled ? "Uninstall command-line tool" : "Install command-line tool",
            action: cliInstalled ? #selector(handleUninstallCLI) : #selector(handleInstallCLI),
            keyEquivalent: ""
        )
        cliItem.target = self
        sub.addItem(cliItem)

        let hookInstalled = ClaudeHookInstaller.isInstalled()
        let hookItem = NSMenuItem(
            title: hookInstalled ? "Uninstall Claude Code integration" : "Install Claude Code integration",
            action: hookInstalled ? #selector(handleUninstallHook) : #selector(handleInstallHook),
            keyEquivalent: ""
        )
        hookItem.target = self
        sub.addItem(hookItem)

        sub.addItem(.separator())

        let autoReadItem = NSMenuItem(
            title: "Auto-read responses",
            action: #selector(handleToggleAutoRead),
            keyEquivalent: ""
        )
        autoReadItem.target = self
        autoReadItem.state = settings.autoReadEnabled ? .on : .off
        sub.addItem(autoReadItem)

        sub.addItem(.separator())
        sub.addItem(buildProjectDisableItem())

        parent.submenu = sub
        return parent
    }

    private func buildProjectDisableItem() -> NSMenuItem {
        guard let cwd = cachedLastSeenCwd else {
            let item = NSMenuItem(
                title: "Disable in current project",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            item.toolTip = "Send a Claude turn first to identify the project"
            return item
        }

        let basename = URL(fileURLWithPath: cwd).lastPathComponent
        let markerPath = (cwd as NSString).appendingPathComponent(".susurro-disable")
        let hasMarker = FileManager.default.fileExists(atPath: markerPath)

        let title = hasMarker ? "Re-enable in \"\(basename)\"" : "Disable in \"\(basename)\""
        let action: Selector = hasMarker ? #selector(handleReenableProject) : #selector(handleDisableProject)
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func handleDisableProject() {
        guard let cwd = cachedLastSeenCwd else { return }
        let markerPath = (cwd as NSString).appendingPathComponent(".susurro-disable")
        do {
            try Data().write(to: URL(fileURLWithPath: markerPath))
        } catch {
            showError(error)
        }
    }

    @objc private func handleReenableProject() {
        guard let cwd = cachedLastSeenCwd else { return }
        let markerPath = (cwd as NSString).appendingPathComponent(".susurro-disable")
        do {
            try FileManager.default.removeItem(atPath: markerPath)
        } catch {
            showError(error)
        }
    }

    @objc private func handleInstallCLI() {
        Task.detached {
            do {
                try CLIInstaller.install()
            } catch {
                await self.showError(error)
            }
            await MainActor.run { self.rebuildMenu() }
        }
    }

    @objc private func handleUninstallCLI() {
        Task.detached {
            do {
                try CLIInstaller.uninstall()
            } catch {
                await self.showError(error)
            }
            await MainActor.run { self.rebuildMenu() }
        }
    }

    @objc private func handleInstallHook() {
        Task.detached {
            do {
                try ClaudeHookInstaller.install()
                await MainActor.run { ClaudeOnboarding.showIfFirstInstall() }
            } catch {
                await self.showError(error)
            }
            await MainActor.run { self.rebuildMenu() }
        }
    }

    @objc private func handleUninstallHook() {
        Task.detached {
            do {
                try ClaudeHookInstaller.uninstall()
            } catch {
                await self.showError(error)
            }
            await MainActor.run { self.rebuildMenu() }
        }
    }

    @MainActor
    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Susurro"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
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
    @objc private func handleToggleAutoRead() { settings.autoReadEnabled.toggle() }
    @objc private func handleToggleTranslateToSpanish() {
        settings.translateToSpanish.toggle()
        rebuildMenu()
    }
    @objc private func handleOpenAccessibility() { AccessibilityPermission.openSystemSettings() }

    @objc private func handleSelectProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = TTSProviderKind(rawValue: raw) else { return }
        if provider == .azure && !settings.azureConfigured {
            TTSConfigWindowController.show(settings: settings) { [weak self] in
                self?.settings.provider = .azure
            }
        } else {
            settings.provider = provider
        }
    }

    @objc private func handleConfigureAzure() {
        TTSConfigWindowController.show(settings: settings) { [weak self] in
            guard let self else { return }
            if self.settings.provider == .azure {
                Task { @MainActor in
                    await TTSProviderRegistry.shared.swap(to: .azure)
                }
            }
        }
    }

    @objc private func handleOpenPronunciations() {
        PronunciationsWindowController.show(settings: settings)
    }

    @objc private func checkForUpdatesTriggered() {
        Task { @MainActor in
            let outcome = await ReleaseChecker.shared.userTriggeredCheck()
            self.presentUpdateOutcome(outcome)
        }
    }

    @MainActor
    private func presentUpdateOutcome(_ outcome: ReleaseChecker.CheckOutcome) {
        let alert = NSAlert()
        switch outcome {
        case .upToDate(let v):
            alert.messageText = "You're up to date"
            alert.informativeText = "Susurro \(v) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .updateAvailable(let info):
            alert.messageText = "Update available: \(info.normalizedVersion)"
            alert.informativeText = "A newer version is available on GitHub."
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Later")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(info.htmlURL)
            }
        case .skipped(let reason), .failed(let reason):
            alert.messageText = "Could not check for updates"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}
