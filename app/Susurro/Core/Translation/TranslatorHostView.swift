import Combine
import SwiftUI
import Translation

// MARK: - Request type

/// A single translation job queued from ``Translator``.
struct TranslationRequest {
    let text: String
    let continuation: CheckedContinuation<String, Error>
}

// MARK: - Translation channel

/// Bridges async callers to the SwiftUI-hosted `TranslationSession`.
///
/// `@MainActor` isolation matches the host view so requests can be enqueued and
/// the view state updated without crossing actor boundaries.
@MainActor
final class TranslationChannel {

    // MARK: Configuration publisher

    private let configSubject = PassthroughSubject<TranslationSession.Configuration, Never>()

    var configurationPublisher: AnyPublisher<TranslationSession.Configuration, Never> {
        configSubject.eraseToAnyPublisher()
    }

    // MARK: Request stream

    private let streamContinuation: AsyncStream<TranslationRequest>.Continuation
    let requests: AsyncStream<TranslationRequest>

    init() {
        let (stream, continuation) = AsyncStream<TranslationRequest>.makeStream()
        self.requests = stream
        self.streamContinuation = continuation
    }

    // MARK: API

    /// Enqueue a translation request and trigger a session refresh on the host view.
    /// Suspends until the host view's `.translationTask` closure resumes the continuation.
    ///
    /// - Throws: `TranslatorError.failed` immediately if the channel is not yet ready
    ///   (i.e. the host view has not initialised its stream). This prevents the caller
    ///   from hanging indefinitely on an unresumable continuation.
    func enqueue(text: String, targetLanguage: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = TranslationRequest(text: text, continuation: continuation)
            guard case .enqueued = streamContinuation.yield(request) else {
                // Stream finished or dropped — resume with an error rather than leaking.
                continuation.resume(throwing: TranslatorError.failed(message: "translation channel closed"))
                return
            }

            // Deliver a fresh configuration so `.translationTask` fires.
            // `invalidate()` bumps the internal version, forcing a re-trigger even if
            // source/target haven't changed since the last call.
            var config = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: targetLanguage)
            )
            config.invalidate()
            configSubject.send(config)
        }
    }
}

// MARK: - Host view

/// Zero-size SwiftUI view that owns the `TranslationSession` lifecycle.
///
/// Embed this in an off-screen `NSWindow` (see ``Translator``) to keep it alive.
struct TranslatorHostView: View {

    @State private var configuration: TranslationSession.Configuration?
    let channel: TranslationChannel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                // `session` is a non-Sendable class delivered into this @escaping closure.
                // Swift 6 strict concurrency flags `await session.translate(...)` as a
                // potential data race because `session` is main-actor-isolated here while
                // `TranslationSession.translate` is nonisolated.
                //
                // `nonisolated(unsafe)` suppresses the diagnostic: we are the sole owner
                // of `session` for the duration of this closure and never share it
                // across actors — the `TranslationSession` docs make no threading
                // guarantees, so callers are responsible for single-task use.
                nonisolated(unsafe) let s = session
                // Drain all requests as they arrive, reusing the same session.
                // We do NOT break after one — SwiftUI's `.translationTask` only re-fires
                // when configuration changes, but `Configuration.==` compares source/target
                // (not version), so identical-language calls would never get a new session.
                // Keeping the loop alive lets us handle every enqueued request with a single
                // session as long as the language pair stays the same.
                for await request in channel.requests {
                    do {
                        try await s.prepareTranslation()
                        let response = try await s.translate(request.text)
                        request.continuation.resume(returning: response.targetText)
                    } catch {
                        request.continuation.resume(throwing: error)
                    }
                }
            }
            .onReceive(channel.configurationPublisher) { newConfig in
                configuration = newConfig
            }
    }
}
