import Foundation

/// Errors that can be thrown by ``Translator``.
enum TranslatorError: Error, Sendable {
    /// The language model has not been downloaded yet; the system will present a download prompt.
    case modelNotReady
    /// A translation request failed. The underlying error description is captured as a plain
    /// `String` so that the enum stays `Sendable` without boxing an `any Error`.
    case failed(message: String)
}

extension TranslatorError: Equatable {}
