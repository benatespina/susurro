import Darwin
import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    let backend = BackendProcess()
    let appState = AppState()
    let ttsSettings = TTSSettings()
    var playbackCoordinator: PlaybackCoordinator?
    private var permissionCoordinator: PermissionCoordinator?
    private var selectionObserver: SelectionObserver?
    private var panelController: PanelController?
    private var accessibilityPollTask: Task<Void, Never>?
    private var menuBarController: MenuBarController?
    private var ipcServer: IPCServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSigtermHandler()
        permissionCoordinator = PermissionCoordinator(appState: appState)
        let coordinator = PlaybackCoordinator(backend: backend)
        playbackCoordinator = coordinator
        installMenuBarController()
        let env = ttsSettings.envVars()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.start(extraEnv: env)
            } catch {
                AppLogger.backend.error("backend start failed: \(error)")
            }
        }
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
                    self.menuBarController?.updatePlayback(
                        isPlaying: snap.isPlaying, isPaused: snap.isPaused
                    )
                }
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await state in await self.backend.states() {
                await MainActor.run {
                    self.appState.update(from: state)
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
    }

    private func installMenuBarController() {
        let controller = MenuBarController(appState: appState, settings: ttsSettings, backend: backend)
        controller.onShowTranscript = { [weak self] in
            guard let self, let coordinator = self.playbackCoordinator else { return }
            TranscriptWindowController.show(
                coordinator: coordinator,
                backend: self.backend,
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
        controller.onRestartBackend = { [weak self] in
            guard let self else { return }
            let env = self.ttsSettings.envVars()
            Task {
                await self.backend.stop()
                try? await self.backend.start(extraEnv: env)
            }
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
                await coordinator.read(text: text)
            }
        }
        panelController?.onStop = { [weak self] in
            Task { await self?.playbackCoordinator?.stop() }
        }
        panelController?.onTeachPronunciation = { [weak self] word in
            guard let self else { return }
            PronunciationsWindowController.show(
                backend: self.backend,
                settings: self.ttsSettings,
                initialWord: word
            )
        }
        AppLogger.selection.info("selection system activated")
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
                await coordinator.read(text: content.text)
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
        guard case .ready(let client) = await backend.state else {
            throw ContentExtractionError.backendNotReady
        }
        let article = try await client.extract(url: url)
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.app.info("applicationShouldTerminate — stopping backend")
        let backend = self.backend
        let ipcServer = self.ipcServer
        Task.detached {
            await ipcServer?.stop()
            await backend.stop()
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
