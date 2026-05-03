import Testing
@testable import Susurro

@Suite("PronunciationsWindowController")
@MainActor
struct PronunciationsWindowControllerTests {
    @Test("normalizeInitialWord with non-empty initialWord returns it")
    func initialWordIsPassedThrough() {
        let word = "encyclopaedia britannica"
        let result = PronunciationsWindowController.normalizeInitialWord(word)
        #expect(result == word)
    }

    @Test("normalizeInitialWord with empty initialWord produces nil")
    func emptyInitialWordBecomesNil() {
        let word = ""
        let result = PronunciationsWindowController.normalizeInitialWord(word)
        #expect(result == nil)
    }

    @Test("normalizeInitialWord with nil initialWord produces nil")
    func nilInitialWordRemainsNil() {
        let word: String? = nil
        let result = PronunciationsWindowController.normalizeInitialWord(word)
        #expect(result == nil)
    }

    @Test("AddPronunciationSheet.Initial captures word verbatim for multi-word phrase")
    func initialWordMultiWordPhrase() {
        let phrase = "encyclopaedia britannica"
        let initial = AddPronunciationSheet.Initial(word: phrase, language: "es", currentReplacement: "")
        #expect(initial.word == phrase)
        #expect(initial.currentReplacement.isEmpty)
    }
}
