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
        MenuBarExtra("Susurro", systemImage: "speaker.wave.2") {
            MenuBarView(backend: appDelegate.backend)
                .environment(appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let backend = BackendProcess()
    let appState = AppState()
    private var permissionCoordinator: PermissionCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSigtermHandler()
        permissionCoordinator = PermissionCoordinator(appState: appState)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.start()
            } catch {
                AppLogger.backend.error("backend start failed: \(error)")
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
        Task.detached {
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
