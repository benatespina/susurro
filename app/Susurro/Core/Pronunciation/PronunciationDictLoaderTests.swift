import Testing
@testable import Susurro

@Suite struct PronunciationDictLoaderTests {

    // MARK: - Bundle loading

    @Test func bundleLoadsAllExpectedEntries() {
        // The original Swift literal had 75 entries; JSON must contain at least that many.
        #expect(esDict.count >= 75)
    }

    @Test func bundleLoadsFrameworkEntry() {
        #expect(esDict["framework"] == "ˈfɾejmwoɾk")
    }

    @Test func bundleLoadsApiEntry() {
        #expect(esDict["api"] == "ˈapi")
    }

    @Test func unicodeIPACharsRoundtrip() {
        // Verify entries that contain IPA characters: ɾ ʃ ŋ ˈ
        #expect(esDict["cache"] == "kaʃ")          // ʃ
        #expect(esDict["string"] == "estɾiŋ")      // ɾ ŋ
        #expect(esDict["framework"] == "ˈfɾejmwoɾk") // ˈ ɾ
        #expect(esDict["push"] == "puʃ")            // ʃ
    }

    // MARK: - Merge helper

    @Test func mergeOverlayWinsForExistingKey() {
        let base = ["api": "ˈapi", "cache": "kaʃ"]
        let overlay = ["api": "custom-pronunciation"]
        let result = PronunciationDictLoader.merge(base: base, overlay: overlay)
        #expect(result["api"] == "custom-pronunciation")
        #expect(result["cache"] == "kaʃ")
    }

    @Test func mergeOverlayAddsNewKeys() {
        let base = ["api": "ˈapi"]
        let overlay = ["newword": "njuˈwoɾd"]
        let result = PronunciationDictLoader.merge(base: base, overlay: overlay)
        #expect(result["newword"] == "njuˈwoɾd")
        #expect(result["api"] == "ˈapi")
        #expect(result.count == 2)
    }

    @Test func mergeEmptyOverlayPreservesBase() {
        let base = ["api": "ˈapi", "cache": "kaʃ"]
        let result = PronunciationDictLoader.merge(base: base, overlay: [:])
        #expect(result == base)
    }

    @Test func mergeEmptyBaseWithOverlay() {
        let overlay = ["framework": "ˈfɾejmwoɾk"]
        let result = PronunciationDictLoader.merge(base: [:], overlay: overlay)
        #expect(result == overlay)
    }

    // MARK: - Fallback

    @Test func fallbackContainsCriticalEntries() {
        let fb = PronunciationDictLoader.fallback
        #expect(fb["api"] == "ˈapi")
        #expect(fb["framework"] == "ˈfɾejmwoɾk")
        #expect(fb["cache"] == "kaʃ")
        #expect(fb.count >= 5)
    }
}
