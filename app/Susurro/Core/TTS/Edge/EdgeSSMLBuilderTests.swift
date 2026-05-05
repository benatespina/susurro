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
        // Microsoft Edge endpoint requires `xml:lang='en-US'` regardless of
        // voice locale (mirrors upstream edge-tts `mkssml` quirk).
        #expect(ssml.contains("xml:lang='en-US'"))
        #expect(ssml.contains("Microsoft Server Speech Text to Speech Voice (es-ES, AlvaroNeural)"))
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
        #expect(ssml.contains("Microsoft Server Speech Text to Speech Voice (en-US, AriaNeural)"))
    }

    @Test("longVoiceName converts short form to long")
    func longVoiceNameTransform() {
        #expect(EdgeSSMLBuilder.longVoiceName("es-ES-AlvaroNeural")
                == "Microsoft Server Speech Text to Speech Voice (es-ES, AlvaroNeural)")
        #expect(EdgeSSMLBuilder.longVoiceName("en-US-AriaNeural")
                == "Microsoft Server Speech Text to Speech Voice (en-US, AriaNeural)")
    }

    // MARK: - Pronunciation behavior

    @Test("does NOT apply pronunciation substitutions (Edge endpoint rejects nested SSML)")
    func skipsPronunciationSubstitutions() async {
        // Microsoft's Edge readaloud WebSocket closes with code 1007 "SSML is
        // invalid" when the body contains <phoneme>, <sub>, <emphasis>, etc.
        // EdgeSSMLBuilder must escape the body as plain text only.
        let ssml = await EdgeSSMLBuilder.build(
            body: "¿dónde estás?",
            language: "es",
            voice: "es-ES-AlvaroNeural"
        )
        #expect(!ssml.contains("<emphasis"))
        #expect(!ssml.contains("<phoneme"))
        #expect(!ssml.contains("<sub "))
        #expect(ssml.contains("dónde"))
    }

    @Test("XML-escapes ampersand and angle brackets in body")
    func escapesXMLSpecials() async {
        let ssml = await EdgeSSMLBuilder.build(
            body: "Tom & Jerry < 5 > 3",
            language: "en",
            voice: "en-US-AriaNeural"
        )
        #expect(ssml.contains("Tom &amp; Jerry &lt; 5 &gt; 3"))
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
