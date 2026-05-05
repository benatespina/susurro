import Foundation

/// Builds SSML documents for the Microsoft Edge TTS WebSocket endpoint.
///
/// The Edge envelope differs from Azure:
/// - Uses `<prosody>` directly under `<voice>` (not `<voice xml:lang=...>`).
/// - Does NOT inject break markers — Edge handles prosody natively.
/// - The xml:lang on `<speak>` is always the RFC-5646 code (e.g. `es-ES`).
///
/// Mirrors Python `edge_tts/communicate.py`'s `mkssml()` function.
enum EdgeSSMLBuilder {

    /// Builds a complete SSML document for Edge TTS synthesis.
    ///
    /// Steps:
    /// 1. Applies pronunciation substitutions via `PronunciationStore.shared.apply`.
    ///    (No `BreakInjector` — Edge does not receive break injection.)
    /// 2. Wraps the escaped body in the Edge SSML envelope.
    ///
    /// - Parameters:
    ///   - body: Raw plain text to synthesize.
    ///   - language: Short language code (`"es"` or `"en"`).
    ///   - voice: Full voice name (e.g. `"es-ES-AlvaroNeural"`).
    /// - Returns: A complete SSML document string.
    static func build(body: String, language: String, voice: String) async -> String {
        // Microsoft's Edge "readaloud" WebSocket endpoint rejects SSML
        // sub-elements (`<phoneme>`, `<sub>`, `<emphasis>`, ...) inside the
        // `<prosody>` wrapper with close code 1007 "SSML is invalid".
        // Only XML-escaped plain text is accepted in this transport.
        // Pronunciation overrides are applied by Azure provider only.
        _ = language
        let escapedBody = SSMLEscape.escape(body)
        return wrap(body: escapedBody, voice: voice)
    }

    // MARK: - Internal

    /// Edge endpoint requires the long-form voice name and a hardcoded
    /// `xml:lang='en-US'` (regardless of voice locale). Both quirks match
    /// upstream `edge_tts/communicate.py:mkssml`.
    static func wrap(body: String, voice: String) -> String {
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(longVoiceName(voice))'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"
            + body
            + "</prosody>"
            + "</voice>"
            + "</speak>"
    }

    /// Converts short voice form (`"es-ES-AlvaroNeural"`) to the Microsoft
    /// long form (`"Microsoft Server Speech Text to Speech Voice (es-ES, AlvaroNeural)"`).
    /// The Edge WebSocket endpoint rejects the short form.
    static func longVoiceName(_ short: String) -> String {
        // "es-ES-AlvaroNeural" → locale="es-ES", short="AlvaroNeural"
        let parts = short.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return short }
        let locale = "\(parts[0])-\(parts[1])"
        let voiceName = String(parts[2])
        return "Microsoft Server Speech Text to Speech Voice (\(locale), \(voiceName))"
    }
}
