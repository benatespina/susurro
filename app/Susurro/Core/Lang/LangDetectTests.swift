import Testing
@testable import Susurro

@Suite struct LangDetectTests {

    @Test func spanishTextDetected() {
        let result = LangDetect.detect("hola mundo, esto es un texto en español de prueba")
        #expect(result == "es")
    }

    @Test func englishTextDetected() {
        let result = LangDetect.detect("this is a sample english sentence used for detection")
        #expect(result == "en")
    }

    @Test func shortTextDefaultsToEnglish() {
        let result = LangDetect.detect("hi")
        #expect(result == "en")
    }

    @Test func emptyTextDefaultsToEnglish() {
        let result = LangDetect.detect("")
        #expect(result == "en")
    }

    @Test func nineCharTextDefaultsToEnglish() {
        // 9 chars (< 10) should default to "en"
        let result = LangDetect.detect("123456789")
        #expect(result == "en")
    }
}
