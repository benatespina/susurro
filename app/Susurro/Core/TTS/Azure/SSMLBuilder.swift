import Foundation

/// Builds Azure SSML documents for TTS synthesis.
enum SSMLBuilder {

    /// Builds a full SSML document for Azure synthesis.
    ///
    /// Steps:
    /// 1. Applies pronunciation substitutions via `PronunciationStore.shared`.
    /// 2. Injects SSML break markers via `BreakInjector`.
    /// 3. Wraps the result in a `<speak><voice>` envelope.
    static func azure(text: String, language: String, voice: String) async -> String {
        let code = TTSConstants.langCode[language] ?? "en-US"
        var body = await PronunciationStore.shared.apply(text: text, language: language)
        body = BreakInjector.inject(body)
        return wrap(body: body, code: code, voice: voice)
    }

    /// Builds a preview SSML document from a raw SSML fragment.
    ///
    /// The fragment is passed through verbatim — no pronunciation substitutions,
    /// no break injection. The caller is responsible for providing valid inner SSML.
    static func azurePreview(ssmlBody: String, language: String, voice: String) -> String {
        let code = TTSConstants.langCode[language] ?? "en-US"
        return wrap(body: ssmlBody, code: code, voice: voice)
    }

    // MARK: - Internal

    static func wrap(body: String, code: String, voice: String) -> String {
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(code)'>"
            + "<voice xml:lang='\(code)' name='\(voice)'>"
            + body
            + "</voice>"
            + "</speak>"
    }
}
