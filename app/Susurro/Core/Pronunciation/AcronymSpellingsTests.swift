import Testing
@testable import Susurro

@Suite struct AcronymSpellingsTests {

    // MARK: - Bundle loading

    @Test func bundleLoadsNonEmpty() {
        #expect(acronymSpellings.count >= 25)
    }

    // MARK: - lookupAcronymSpelling

    @Test func lookupAPIReturnsExpectedSpelling() {
        #expect(lookupAcronymSpelling("API") == "éi pi ái")
    }

    @Test func lookupIsLowercaseCaseInsensitive() {
        #expect(lookupAcronymSpelling("api") == lookupAcronymSpelling("API"))
    }

    @Test func lookupMixedCaseIsCaseInsensitive() {
        #expect(lookupAcronymSpelling("Api") == lookupAcronymSpelling("API"))
    }

    @Test func lookupUnknownAcronymReturnsNil() {
        #expect(lookupAcronymSpelling("XYZ") == nil)
    }

    // MARK: - Fallback

    @Test func fallbackContainsCriticalEntries() {
        let fb = AcronymSpellingsLoader.fallback
        #expect(fb["API"] == "éi pi ái")
        #expect(fb["URL"] == "yu erre éle")
        #expect(fb["HTML"] == "éich ti emé éle")
        #expect(fb["JSON"] == "yéison")
        #expect(fb["HTTP"] == "éich ti ti pi")
        #expect(fb.count >= 3)
    }

    // MARK: - Merge helper

    @Test func mergeOverlayWinsForExistingKey() {
        let base = ["API": "éi pi ái", "URL": "yu erre éle"]
        let overlay = ["API": "a pe i"]
        let result = AcronymSpellingsLoader.merge(base: base, overlay: overlay)
        #expect(result["API"] == "a pe i")
        #expect(result["URL"] == "yu erre éle")
    }

    @Test func mergeOverlayAddsNewKeys() {
        let base = ["API": "éi pi ái"]
        let overlay = ["NEWACR": "nu ak ro nim"]
        let result = AcronymSpellingsLoader.merge(base: base, overlay: overlay)
        #expect(result["NEWACR"] == "nu ak ro nim")
        #expect(result["API"] == "éi pi ái")
        #expect(result.count == 2)
    }

    @Test func mergeEmptyOverlayPreservesBase() {
        let base = ["API": "éi pi ái", "URL": "yu erre éle"]
        let result = AcronymSpellingsLoader.merge(base: base, overlay: [:])
        #expect(result == base)
    }
}
