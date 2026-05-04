import Testing
@testable import Susurro

@Suite struct PronunciationDictTests {

    // MARK: - isAcronym

    @Test func acronymSetHit() {
        #expect(isAcronym("API") == true)
        #expect(isAcronym("HTTP") == true)
        #expect(isAcronym("JSON") == true)
        #expect(isAcronym("URL") == true)
    }

    @Test func fourLetterCapsDetected() {
        // A 4-letter all-caps ASCII word not in the set is still detected
        #expect(isAcronym("ABCD") == true)
        #expect(isAcronym("ZZZZ") == true)
    }

    @Test func mixedCaseRejected() {
        #expect(isAcronym("Api") == false)
        #expect(isAcronym("http") == false)
        #expect(isAcronym("JavaScript") == false)
    }

    @Test func singleCharRejected() {
        #expect(isAcronym("A") == false)
    }

    @Test func sevenLetterCapsRejected() {
        // 7 chars exceeds the 2...6 range
        #expect(isAcronym("ABCDEFG") == false)
    }

    // MARK: - lookupIPA

    @Test func lookupIPAHitsForSpanish() {
        let ipa = lookupIPA(word: "api", language: "es")
        #expect(ipa == "ˈapi")
    }

    @Test func lookupIPACaseInsensitive() {
        let ipa = lookupIPA(word: "API", language: "es")
        #expect(ipa == "ˈapi")
    }

    @Test func lookupIPAMissForEnglish() {
        // Dict is Spanish-only
        let ipa = lookupIPA(word: "api", language: "en")
        #expect(ipa == nil)
    }

    @Test func lookupIPAUnknownWordReturnsNil() {
        let ipa = lookupIPA(word: "zylophone", language: "es")
        #expect(ipa == nil)
    }

    @Test func lookupIPAKnownWords() {
        #expect(lookupIPA(word: "backend", language: "es") == "bakˈend")
        #expect(lookupIPA(word: "cache", language: "es") == "kaʃ")
        #expect(lookupIPA(word: "deploy", language: "es") == "deˈploj")
    }
}
