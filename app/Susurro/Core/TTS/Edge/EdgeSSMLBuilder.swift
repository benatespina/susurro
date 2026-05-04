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
        let code = TTSConstants.langCode[language] ?? "en-US"
        let escapedBody = await PronunciationStore.shared.apply(text: body, language: language)
        return wrap(body: escapedBody, code: code, voice: voice)
    }

    // MARK: - Internal

    static func wrap(body: String, code: String, voice: String) -> String {
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(code)'>"
            + "<voice name='\(voice)'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"
            + body
            + "</prosody>"
            + "</voice>"
            + "</speak>"
    }
}
