import Testing
import Foundation
@testable import Susurro

@Suite("SSMLBuilder")
struct SSMLBuilderTests {

    // MARK: - azure(text:language:voice:)

    @Test("empty body produces minimal valid envelope")
    func emptyBodyProducesEnvelope() async {
        let result = await SSMLBuilder.azure(text: "", language: "en", voice: "en-US-AriaNeural")
        #expect(result.contains("<speak"))
        #expect(result.contains("<voice"))
        #expect(result.contains("</speak>"))
    }

    @Test("Spanish text sets xml:lang to es-ES and voice to AlvaroNeural")
    func spanishLangAndVoice() async {
        let result = await SSMLBuilder.azure(
            text: "Hola mundo",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        #expect(result.contains("xml:lang='es-ES'"))
        #expect(result.contains("name='es-ES-AlvaroNeural'"))
    }

    @Test("English text sets xml:lang to en-US and voice to AriaNeural")
    func englishLangAndVoice() async {
        let result = await SSMLBuilder.azure(
            text: "Hello world",
            language: "en",
            voice: "en-US-AriaNeural"
        )
        #expect(result.contains("xml:lang='en-US'"))
        #expect(result.contains("name='en-US-AriaNeural'"))
    }

    @Test("pronunciation store default seed applies emphasis to 'dónde'")
    func pronunciationDefaultSeedApplied() async {
        // PronunciationStore.shared seeds "dónde" → <emphasis level="moderate">dónde</emphasis>
        let result = await SSMLBuilder.azure(
            text: "¿dónde estás?",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        #expect(result.contains("<emphasis"))
        #expect(result.contains("dónde"))
    }

    @Test("break injection fires: single newline in body becomes 300ms break")
    func breakInjectionFires() async {
        let result = await SSMLBuilder.azure(
            text: "line one\nline two",
            language: "en",
            voice: "en-US-AriaNeural"
        )
        #expect(result.contains("<break time=\"300ms\"/>"))
    }

    // MARK: - azurePreview(ssmlBody:language:voice:)

    @Test("azurePreview passes raw body through unchanged")
    func previewPassesBodyUnchanged() {
        let rawBody = "<phoneme alphabet=\"ipa\" ph=\"hə.ˈloʊ\">hello</phoneme>"
        let result = SSMLBuilder.azurePreview(
            ssmlBody: rawBody,
            language: "en",
            voice: "en-US-AriaNeural"
        )
        #expect(result.contains(rawBody))
    }

    @Test("azurePreview does not run break injection on newlines")
    func previewNoBreakInjection() {
        let body = "line one\nline two"
        let result = SSMLBuilder.azurePreview(
            ssmlBody: body,
            language: "en",
            voice: "en-US-AriaNeural"
        )
        // The body should be present verbatim — no break replacement
        #expect(result.contains("line one\nline two"))
        #expect(!result.contains("<break"))
    }

    @Test("azurePreview does not escape HTML entities in raw body")
    func previewNoEscape() {
        let body = "<sub alias=\"kss\">CSS</sub>"
        let result = SSMLBuilder.azurePreview(
            ssmlBody: body,
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        // Must not double-escape; raw SSML must survive
        #expect(result.contains("<sub alias=\"kss\">CSS</sub>"))
        #expect(!result.contains("&lt;"))
    }

    @Test("azurePreview wraps body in speak/voice envelope for es-ES")
    func previewEnvelopeSpanish() {
        let result = SSMLBuilder.azurePreview(
            ssmlBody: "test",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        #expect(result.contains("xml:lang='es-ES'"))
        #expect(result.contains("name='es-ES-AlvaroNeural'"))
    }
}
