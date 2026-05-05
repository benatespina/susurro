import Testing
import Foundation
@testable import Susurro

@Suite("BreakInjector")
struct BreakInjectorTests {

    @Test("empty string returns empty")
    func emptyString() {
        #expect(BreakInjector.inject("") == "")
    }

    @Test("plain ASCII text without newlines or terminal punctuation is unchanged")
    func plainAsciiUnchanged() {
        let input = "Hello world this is plain text"
        #expect(BreakInjector.inject(input) == input)
    }

    @Test("single newline becomes 300ms line break")
    func singleNewline() {
        let result = BreakInjector.inject("line one\nline two")
        #expect(result == "line one<break time=\"300ms\"/>line two")
    }

    @Test("double newline becomes 700ms paragraph break")
    func doubleNewline() {
        let result = BreakInjector.inject("para one\n\npara two")
        #expect(result == "para one<break time=\"700ms\"/>para two")
    }

    @Test("mixed multiple newlines with whitespace becomes single 700ms break")
    func multipleNewlinesWithWhitespace() {
        let result = BreakInjector.inject("para one\n\n  \npara two")
        #expect(result == "para one<break time=\"700ms\"/>para two")
    }

    @Test("U+FFFC object replacement character becomes 700ms paragraph break")
    func objectReplacementChar() {
        let result = BreakInjector.inject("before\u{FFFC}after")
        #expect(result == "before<break time=\"700ms\"/>after")
    }

    @Test("multiple U+FFFC in a row collapse to single 700ms break")
    func multipleObjectReplacementChars() {
        let result = BreakInjector.inject("\u{FFFC}\u{FFFC}\u{FFFC}")
        #expect(result == "<break time=\"700ms\"/>")
    }

    @Test("period followed by uppercase letter inserts 700ms break with space")
    func periodBeforeUppercase() {
        let result = BreakInjector.inject("Hola.Mundo")
        #expect(result == "Hola.<break time=\"700ms\"/> Mundo")
    }

    @Test("exclamation followed by uppercase letter inserts 700ms break")
    func exclamationBeforeUppercase() {
        let result = BreakInjector.inject("Stop!Now")
        #expect(result == "Stop!<break time=\"700ms\"/> Now")
    }

    @Test("question mark followed by uppercase Spanish letter inserts 700ms break")
    func questionBeforeSpanishUppercase() {
        let result = BreakInjector.inject("¿Cómo estás?Álvaro")
        // Rule 4 matches [.!?] followed by [A-ZÁÉÍÓÚÑ]
        #expect(result.contains("<break time=\"700ms\"/>"))
    }

    @Test("rules apply in order: FFFC fires rule 1, single newline fires rule 3")
    func rulesApplyInOrder() {
        // U+FFFC → rule 1 (700ms), single \n → rule 3 (300ms)
        let result = BreakInjector.inject("\u{FFFC}\n")
        #expect(result == "<break time=\"700ms\"/><break time=\"300ms\"/>")
    }

    @Test("rule 4 does not fire when punctuation is followed by a space")
    func rule4DoesNotFireWithSpace() {
        let input = "Hello. World"
        #expect(BreakInjector.inject(input) == input)
    }
}
