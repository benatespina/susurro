import Testing
@testable import Susurro

@Suite struct PronunciationRulesTests {

    // MARK: - enToIPAEs

    @Test func scriptStartsWithE() {
        // "script" → starts with 's' + consonant → prepend 'e'
        let result = PronunciationRules.enToIPAEs("script")
        #expect(result.hasPrefix("e"))
    }

    @Test func shBecomesIPAFricative() {
        // "sh" → "ʃ"
        let result = PronunciationRules.enToIPAEs("ship")
        #expect(result.contains("ʃ"))
    }

    @Test func chBecomesAffricate() {
        let result = PronunciationRules.enToIPAEs("chat")
        #expect(result.contains("tʃ"))
    }

    @Test func ingEnding() {
        let result = PronunciationRules.enToIPAEs("running")
        #expect(result.hasSuffix("iŋ"))
    }

    @Test func erEnding() {
        let result = PronunciationRules.enToIPAEs("router")
        #expect(result.hasSuffix("eɾ"))
    }

    @Test func tionEnding() {
        let result = PronunciationRules.enToIPAEs("section")
        #expect(result.hasSuffix("ʃon"))
    }

    @Test func yFinalBecomesI() {
        let result = PronunciationRules.enToIPAEs("party")
        #expect(result.hasSuffix("i"))
    }

    // MARK: - transliterateToEs

    @Test func javascriptIncludesY() {
        let result = PronunciationRules.transliterateToEs("javascript")
        #expect(result.contains("y"))
    }

    @Test func shInTranslit() {
        let result = PronunciationRules.transliterateToEs("shell")
        #expect(result.contains("sh"))
    }

    @Test func thConvertedAndZBecomesS() {
        // "think" → th→z gives "zink", then z→s gives "sink"
        // The z→s rule runs after th→z, so the final output is "sink"
        let result = PronunciationRules.transliterateToEs("think")
        #expect(result == "sink")
    }

    @Test func wBecomesU() {
        let result = PronunciationRules.transliterateToEs("web")
        #expect(result.contains("u"))
    }

    @Test func ingBecomeIn() {
        let result = PronunciationRules.transliterateToEs("testing")
        #expect(result.hasSuffix("in"))
    }

    @Test func stackEpenthesis() {
        // "stack" → "stak" after ck→k, then starts with s+consonant → "estak"
        let result = PronunciationRules.transliterateToEs("stack")
        #expect(result.hasPrefix("e"))
    }

    @Test func noEpenthesisWhenStartsWithSVowel() {
        // "sea" → after "ea"→"i": "si" — starts with s followed by vowel, no prepend
        let result = PronunciationRules.transliterateToEs("sea")
        #expect(result == "si")
    }
}
