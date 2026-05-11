import Combine
import Darwin
import SwiftUI
import UserNotifications

@main struct SusurroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Block SIGTERM in the main thread before NSApp spawns worker threads.
        // All threads inherit this mask, preventing the OS default handler from
        // killing the process. AppDelegate.installSigtermHandler() catches the
        // signal via sigwait on a dedicated thread and routes it through
        // applicationShouldTerminate for graceful backend cleanup.
        var mask = sigset_t()
        sigemptyset(&mask)
        sigaddset(&mask, SIGTERM)
        pthread_sigmask(SIG_BLOCK, &mask, nil)
        AppLogger.app.info("Susurro launched")
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let appState = AppState()
    let ttsSettings = TTSSettings()
    var playbackCoordinator: PlaybackCoordinator?
    private var permissionCoordinator: PermissionCoordinator?
    private var selectionObserver: SelectionObserver?
    private var panelController: PanelController?
    private var accessibilityPollTask: Task<Void, Never>?
    private var menuBarController: MenuBarController?
    private var ipcServer: IPCServer?
    private var registryCancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSigtermHandler()
        permissionCoordinator = PermissionCoordinator(appState: appState)
        let settings = ttsSettings
        let coordinator = PlaybackCoordinator(
            translator: Translator.shared,
            isTranslateToSpanishEnabled: { [weak settings] in settings?.translateToSpanish ?? false }
        )
        playbackCoordinator = coordinator
        let socketPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Susurro/ipc.sock")
            .path
        let server = IPCServer(socketPath: socketPath, speaker: coordinator, settings: ttsSettings)
        ipcServer = server
        Task {
            do {
                try await server.start()
            } catch {
                AppLogger.app.error("IPCServer start failed: \(error, privacy: .public)")
            }
        }
        installMenuBarController()

        // Warm up the TTS registry (live-swap provider).
        Task { @MainActor in
            await TTSProviderRegistry.shared.warmup()
        }

        // Wire registry readiness to AppState.backendStatus.
        TTSProviderRegistry.shared.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                guard let self else { return }
                self.appState.backendStatus = ready ? .ready : .starting
            }
            .store(in: &registryCancellables)

        Task { [weak self] in
            guard let self, let coordinator = self.playbackCoordinator else { return }
            await coordinator.restorePersistedSession()
            let restored = await coordinator.hasRestorableSession()
            await MainActor.run { self.appState.hasResumableSession = restored }
        }
        Task { [weak self] in
            guard let self, let coordinator = self.playbackCoordinator else { return }
            for await snap in await coordinator.snapshots() {
                await MainActor.run {
                    self.appState.hasResumableSession = !snap.chunks.isEmpty
                    self.appState.isPaused = snap.isPaused
                    self.appState.currentRate = snap.currentRate
                    self.menuBarController?.updatePlayback(
                        isPlaying: snap.isPlaying, isPaused: snap.isPaused
                    )
                    self.menuBarController?.updateRate(snap.currentRate)
                }
            }
        }
        Task { [weak self] in
            guard let self, let pc = self.playbackCoordinator else { return }
            for await playing in await pc.playingStates() {
                await MainActor.run {
                    self.appState.isPlaying = playing
                    self.menuBarController?.updatePlayback(
                        isPlaying: playing, isPaused: self.appState.isPaused
                    )
                }
            }
        }
        startSelectionSystemWhenPermitted()
        registerReadThisHotkey()

        // Set notification delegate so taps open the release page.
        UNUserNotificationCenter.current().delegate = self

        // Kick off update check after a short delay so it doesn't compete with launch I/O.
        Task.detached {
            try? await Task.sleep(for: .seconds(5))
            await ReleaseChecker.shared.checkIfDue()
        }
    }

    private func installMenuBarController() {
        guard let server = ipcServer else { return }
        let controller = MenuBarController(appState: appState, settings: ttsSettings, ipcServer: server)
        controller.onShowTranscript = { [weak self] in
            guard let self, let coordinator = self.playbackCoordinator else { return }
            TranscriptWindowController.show(
                coordinator: coordinator,
                settings: self.ttsSettings
            )
        }
        controller.onResumeReading = { [weak self] in
            guard let coordinator = self?.playbackCoordinator else { return }
            Task {
                let snap = await coordinator.currentSnapshot()
                guard !snap.chunks.isEmpty else { return }
                await coordinator.seek(toChunk: snap.currentChunkIndex)
            }
        }
        controller.onReadThis = { [weak self] in
            self?.readFromCurrentApp()
        }
        controller.onTogglePause = { [weak self] in
            Task { @MainActor [weak self] in
                guard let coordinator = self?.playbackCoordinator else { return }
                let snap = await coordinator.currentSnapshot()
                if snap.isPaused {
                    await coordinator.resume()
                } else {
                    await coordinator.pause()
                }
            }
        }
        controller.onStop = { [weak self] in
            Task { await self?.playbackCoordinator?.stop() }
        }
        controller.onSpeedDown = { [weak self] in self?.cycleSpeedDown() }
        controller.onSpeedUp = { [weak self] in self?.cycleSpeedUp() }
        menuBarController = controller
    }

    private func registerReadThisHotkey() {
        GlobalHotkeyManager.shared.register(
            keyCode: HotkeyDefaults.readThisKeyCode,
            modifiers: HotkeyDefaults.readThisModifiers
        ) { [weak self] in
            self?.readFromCurrentApp()
        }
        AppLogger.app.info("global hotkey Cmd+Option+R registered for Read this")
    }

    private func startSelectionSystemWhenPermitted() {
        if appState.accessibilityStatus == .granted {
            activateSelectionSystem()
            return
        }
        accessibilityPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.appState.accessibilityStatus == .granted {
                    self.activateSelectionSystem()
                    return
                }
            }
        }
    }

    private func activateSelectionSystem() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = nil
        guard selectionObserver == nil else { return }
        selectionObserver = SelectionObserver()
        panelController = PanelController(observer: selectionObserver!, appState: appState)
        panelController?.onRead = { [weak self] text in
            AppLogger.selection.info("read requested for: \(text.prefix(60), privacy: .public)")
            Task { @MainActor in
                guard let self, let coordinator = self.playbackCoordinator else { return }
                _ = await coordinator.read(text: text)
            }
        }
        panelController?.onStop = { [weak self] in
            Task { await self?.playbackCoordinator?.stop() }
        }
        panelController?.onTeachPronunciation = { [weak self] word in
            guard let self else { return }
            PronunciationsWindowController.show(
                settings: self.ttsSettings,
                initialWord: word
            )
        }
        AppLogger.selection.info("selection system activated")
    }

    private func cycleSpeedDown() {
        let previous = PlaybackSpeed.previous(from: appState.currentRate)
        // Update optimistically so rapid successive clicks read the new value,
        // not the stale pre-Task value (the snapshot loop will confirm it shortly).
        appState.currentRate = previous
        Task { await self.playbackCoordinator?.setRate(previous) }
    }

    private func cycleSpeedUp() {
        let next = PlaybackSpeed.next(from: appState.currentRate)
        // Update optimistically so rapid successive clicks read the new value,
        // not the stale pre-Task value (the snapshot loop will confirm it shortly).
        appState.currentRate = next
        Task { await self.playbackCoordinator?.setRate(next) }
    }

    func readFromCurrentApp() {
        let resolved = SourceResolver.resolve()
        let fallback: String? = resolved == nil ? Self.urlFromClipboard() : nil
        if resolved == nil && fallback == nil {
            AppLogger.app.info("no readable source in frontmost app or clipboard")
            NSSound.beep()
            return
        }
        Task { [weak self] in
            guard let self, let coordinator = self.playbackCoordinator else { return }
            do {
                let content = try await self.extractContent(
                    resolved: resolved, clipboardURL: fallback
                )
                AppLogger.app.info("read source title=\(content.title ?? "-", privacy: .public) chars=\(content.text.count, privacy: .public)")
                _ = await coordinator.read(text: content.text)
            } catch {
                AppLogger.app.error("read source failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    private func extractContent(
        resolved: ResolvedSource?, clipboardURL: String?
    ) async throws -> ResolvedContent {
        if let resolved {
            switch resolved {
            case .browserURL(let url):
                return try await fetchArticle(url: url)
            case .pdfFile(let url):
                return try PDFKitSource.extractText(from: url)
            case .fullText(let text, let title):
                return ResolvedContent(text: text, title: title, language: nil)
            }
        }
        if let url = clipboardURL {
            return try await fetchArticle(url: url)
        }
        throw ContentExtractionError.noSource
    }

    private func fetchArticle(url: String) async throws -> ResolvedContent {
        if Self.urlLooksLikePDF(url), let parsed = URL(string: url) {
            AppLogger.app.info("source: browser URL is PDF, downloading via PDFKit")
            return try await PDFKitSource.extractText(fromRemote: parsed)
        }
        let health = await BackendClient.shared.health()
        guard health == .ready else {
            throw ContentExtractionError.backendNotReady
        }
        let article = try await BackendClient.shared.extract(url: url)
        return ResolvedContent(
            text: article.text, title: article.title, language: article.language
        )
    }

    private static func urlLooksLikePDF(_ raw: String) -> Bool {
        guard let parsed = URL(string: raw) else { return false }
        return parsed.path.lowercased().hasSuffix(".pdf")
    }

    private static func urlFromClipboard() -> String? {
        let pb = NSPasteboard.general
        let raw = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let parsed = URL(string: raw),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false
        else { return nil }
        return parsed.absoluteString
    }

    private func installSigtermHandler() {
        Thread.detachNewThread {
            var sigset = sigset_t()
            sigemptyset(&sigset)
            sigaddset(&sigset, SIGTERM)
            var sig: Int32 = 0
            sigwait(&sigset, &sig)
            AppLogger.app.info("SIGTERM received — initiating graceful shutdown")
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["releaseURL"] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.app.info("applicationShouldTerminate — stopping IPC server")
        let ipcServer = self.ipcServer
        Task.detached {
            await ipcServer?.stop()
            // NSApp.terminate's modal loop runs in NSModalRunLoopMode, which is
            // excluded from NSRunLoopCommonModes. DispatchQueue.main and
            // await MainActor.run use NSDefaultRunLoopMode and are not processed
            // during the modal wait. Scheduling via RunLoop.main with the modal
            // mode ensures reply fires while terminate is blocking.
            let senderApp = sender
            RunLoop.main.perform(inModes: [.modalPanel, .default]) {
                // RunLoop.perform always fires on the main thread, satisfying
                // the main-actor isolation requirement of reply(toApplication...).
                MainActor.assumeIsolated { senderApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }
}
