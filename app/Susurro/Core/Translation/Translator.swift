import AppKit
import SwiftUI
import Translation

// MARK: - Protocol

/// Dependency-injection seam so downstream consumers (and tests) can swap in a mock.
protocol TranslatorProviding: Sendable {
    /// Translates `text` to `targetLanguage` (BCP-47 tag, e.g. `"es"`).
    ///
    /// - Returns: the translated string. Returns `text` unchanged if it is blank
    ///   (empty or whitespace-only) without invoking the Translation framework.
    /// - Throws: `TranslatorError` on failure.
    func translate(_ text: String, to targetLanguage: String) async throws -> String
}

// MARK: - TranslationGate

/// Serializes translation requests so that at most one is in-flight through the
/// SwiftUI-hosted channel at a time. Concurrent callers wait their turn in FIFO order.
private actor TranslationGate {
    private var tail: Task<Void, Never> = Task {}

    /// Enqueues `work` behind the current tail task and returns when `work` completes.
    ///
    /// - Throws: rethrows whatever `work` throws, or `CancellationError` if the
    ///   calling task is cancelled while waiting.
    func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        // Snapshot and advance the tail while still on the actor.
        let previous = tail
        let barrier = Task<T, Error> {
            // Wait for whoever was previously in-flight to finish.
            await previous.value
            // Propagate caller cancellation rather than silently continuing.
            try Task.checkCancellation()
            return try await work()
        }
        // Erase the result type so the stored tail is always Task<Void, Never>.
        tail = Task { _ = await barrier.result }
        return try await barrier.value
    }
}

// MARK: - Translator

/// Translates text using the on-device Apple Translation framework (macOS 15+).
///
/// ## Architecture
/// `TranslationSession` can only be obtained inside a SwiftUI `.translationTask`
/// modifier. `Translator` installs a hidden `NSWindow` that hosts a
/// `TranslatorHostView` off-screen. Translation requests flow through
/// `TranslationChannel` (a `@MainActor` bridge) which the host view drains each
/// time a new `TranslationSession.Configuration` is published.
///
/// ## Smoke tests
/// Real `TranslationSession` calls are gated behind the env var
/// `SUSURRO_TRANSLATION_SMOKE=1`. CI never sets that variable, so automated test
/// runs stay fast and offline. Run locally with:
/// ```
/// SUSURRO_TRANSLATION_SMOKE=1 xcodebuild test …
/// ```
@MainActor
final class Translator: TranslatorProviding {

    // MARK: - Singleton

    static let shared = Translator()

    // MARK: - Private state

    private let channel = TranslationChannel()
    private let gate = TranslationGate()
    /// Off-screen window keeping the SwiftUI host alive for the lifetime of the app.
    private var hostWindow: NSWindow?

    // MARK: - Init

    init() {
        installHostView()
    }

    // MARK: - Public API

    /// Translates `text` to `targetLanguage`.
    ///
    /// - Blank text (empty or whitespace-only) is returned as-is without invoking
    ///   the Translation framework.
    /// - Source language is left as `nil` so Apple auto-detects it.
    /// - If the language model has not been downloaded, Apple presents its own
    ///   download-consent UI on first call. After the user accepts, subsequent
    ///   calls succeed. (Not automatically testable — see smoke tests.)
    nonisolated func translate(_ text: String, to targetLanguage: String) async throws -> String {
        // Short-circuit blank text — no framework call needed.
        // Returns the original string (not "") so callers receive the same value back
        // and the documented contract ("returns text unchanged if empty") is satisfied.
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }

        do {
            // `gate.run` serializes concurrent callers so that only one request reaches
            // the channel at a time. SwiftUI cannot coalesce two configuration publications
            // that are delivered sequentially. `channel` is `@MainActor`-isolated;
            // the `await` hops to the main actor automatically.
            let translated = try await gate.run {
                try await self.channel.enqueue(text: text, targetLanguage: targetLanguage)
            }
            AppLogger.translation.debug("Translated \(text.count, privacy: .public) chars → \(targetLanguage, privacy: .public)")
            return translated
        } catch let error as TranslationError {
            AppLogger.translation.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            if case .notInstalled = error {
                throw TranslatorError.modelNotReady
            }
            throw TranslatorError.failed(message: error.localizedDescription)
        } catch {
            AppLogger.translation.error("Translation error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Private helpers

    private func installHostView() {
        let hostView = TranslatorHostView(channel: channel)
        let hosting = NSHostingView(rootView: hostView)
        hosting.frame = .zero

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.title = "Susurro Translation"
        window.level = .normal
        window.orderFront(nil) // ordered into window list but off-screen so sheets can attach
        hostWindow = window

        AppLogger.translation.debug("TranslatorHostView installed in off-screen window")
    }
}
