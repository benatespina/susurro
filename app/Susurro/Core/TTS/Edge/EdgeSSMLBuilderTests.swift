import Foundation
import Testing
@testable import Susurro

@Suite("EdgeSSMLBuilder")
struct EdgeSSMLBuilderTests {

    // MARK: - Envelope structure

    @Test("wraps Spanish text in correct Edge SSML envelope")
    func wrapsSpanishText() async {
        let ssml = await EdgeSSMLBuilder.build(
            body: "Hola mundo",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )

        #expect(ssml.contains("<speak version='1.0'"))
        #expect(ssml.contains("xml:lang='es-ES'"))
        #expect(ssml.contains("<voice name='es-ES-AlvaroNeural'>"))
        #expect(ssml.contains("<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"))
        #expect(ssml.contains("</prosody>"))
        #expect(ssml.contains("</voice>"))
        #expect(ssml.contains("</speak>"))
    }

    @Test("wraps English text in correct Edge SSML envelope")
    func wrapsEnglishText() async {
        let ssml = await EdgeSSMLBuilder.build(
            body: "Hello world",
            language: "en",
            voice: "en-US-AriaNeural"
        )

        #expect(ssml.contains("xml:lang='en-US'"))
        #expect(ssml.contains("<voice name='en-US-AriaNeural'>"))
    }

    @Test("uses en-US as fallback for unknown language")
    func fallsBackToEnUS() {
        let ssml = EdgeSSMLBuilder.wrap(body: "text", code: "en-US", voice: "en-US-AriaNeural")
        #expect(ssml.contains("xml:lang='en-US'"))
    }

    // MARK: - Pronunciation application

    @Test("applies pronunciation substitutions from default seed")
    func appliesPronunciationSubstitutions() async {
        // The default seed maps "dónde" → <emphasis level="moderate">dónde</emphasis>
        let ssml = await EdgeSSMLBuilder.build(
            body: "¿dónde estás?",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        #expect(ssml.contains("<emphasis"))
        #expect(ssml.contains("dónde"))
    }

    // MARK: - No break injection

    @Test("does NOT inject break tags for newlines")
    func doesNotInjectBreaks() async {
        let textWithNewlines = "Primera línea.\nSegunda línea.\nTercera línea."
        let ssml = await EdgeSSMLBuilder.build(
            body: textWithNewlines,
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        // Edge must never contain <break> — that's Azure-only
        #expect(!ssml.contains("<break"))
    }

    @Test("does NOT inject break tags for multiple newlines")
    func doesNotInjectBreaksMultipleNewlines() async {
        let textWithParagraphs = "Párrafo uno.\n\nPárrafo dos.\n\nPárrafo tres."
        let ssml = await EdgeSSMLBuilder.build(
            body: textWithParagraphs,
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        #expect(!ssml.contains("<break"))
    }

    // MARK: - No Azure structure

    @Test("does NOT use Azure voice xml:lang attribute")
    func doesNotHaveAzureVoiceLangAttribute() async {
        let ssml = await EdgeSSMLBuilder.build(
            body: "test",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        // Azure has <voice xml:lang='...'> but Edge uses <voice name='...'>
        #expect(!ssml.contains("voice xml:lang="))
    }
}
