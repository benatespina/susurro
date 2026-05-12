import Testing
@testable import Susurro

@Suite struct AcronymSpellingsTests {

    // MARK: - Bundle loading

    @Test func bundleLoadsNonEmpty() {
        #expect(acronymSpellings.count >= 25)
    }

    // MARK: - lookupAcronymSpelling

    @Test func lookupAPIReturnsExpectedSpelling() {
        #expect(lookupAcronymSpelling("API") == "ei pi ay")
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
        #expect(fb["API"] == "ei pi ay")
        #expect(fb["URL"] == "yu ar el")
        #expect(fb["HTML"] == "eich ti em el")
        #expect(fb["JSON"] == "yeison")
        #expect(fb["HTTP"] == "eich ti ti pi")
        #expect(fb.count >= 3)
    }

    // MARK: - Merge helper

    @Test func mergeOverlayWinsForExistingKey() {
        let base = ["API": "ei pi ay", "URL": "yu ar el"]
        let overlay = ["API": "a pe i"]
        let result = AcronymSpellingsLoader.merge(base: base, overlay: overlay)
        #expect(result["API"] == "a pe i")
        #expect(result["URL"] == "yu ar el")
    }

    @Test func mergeOverlayAddsNewKeys() {
        let base = ["API": "ei pi ay"]
        let overlay = ["NEWACR": "nu ak ro nim"]
        let result = AcronymSpellingsLoader.merge(base: base, overlay: overlay)
        #expect(result["NEWACR"] == "nu ak ro nim")
        #expect(result["API"] == "ei pi ay")
        #expect(result.count == 2)
    }

    @Test func mergeEmptyOverlayPreservesBase() {
        let base = ["API": "ei pi ay", "URL": "yu ar el"]
        let result = AcronymSpellingsLoader.merge(base: base, overlay: [:])
        #expect(result == base)
    }
}
