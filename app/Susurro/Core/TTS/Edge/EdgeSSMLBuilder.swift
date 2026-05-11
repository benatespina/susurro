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
    /// The supplied `pronunciationsApply` closure is the SOLE source of body
    /// content emitted to the WebSocket. It MUST return an Edge-safe string:
    /// XML-escaped plain text (no SSML sub-elements — Edge rejects them with
    /// close code 1007). The builder does not escape — re-escaping would
    /// double-encode `&amp;`. Trust-but-verify lives in EdgeSSMLBuilderTests.
    ///
    /// - Parameters:
    ///   - body: Raw plain text to synthesize.
    ///   - language: Short language code (`"es"` or `"en"`).
    ///   - voice: Full voice name (e.g. `"es-ES-AlvaroNeural"`).
    ///   - pronunciationsApply: Closure that returns an Edge-safe, XML-escaped string.
    /// - Returns: A complete SSML document string.
    static func build(
        body: String,
        language: String,
        voice: String,
        pronunciationsApply: @Sendable (String, String) async -> String
    ) async -> String {
        let safeBody = await pronunciationsApply(body, language)
        return wrap(body: safeBody, voice: voice)
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
