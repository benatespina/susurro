import Testing
import Foundation
@testable import Susurro

@Suite struct PronunciationStoreTests {

    private func makeStore() -> PronunciationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("susurro-test-\(UUID().uuidString).json")
        return PronunciationStore(fileURL: url)
    }

    // MARK: - CRUD

    @Test func upsertAndList() async throws {
        let store = makeStore()
        try await store.upsert(language: "es", word: "javascript", replacement: "yabascript")
        let all = await store.listAll()
        #expect(all["es"]?["javascript"] == "yabascript")
    }

    @Test func upsertOverwrites() async throws {
        let store = makeStore()
        try await store.upsert(language: "es", word: "api", replacement: "a-pi")
        try await store.upsert(language: "es", word: "api", replacement: "ˈapi")
        let all = await store.listAll()
        #expect(all["es"]?["api"] == "ˈapi")
    }

    @Test func removeWord() async throws {
        let store = makeStore()
        try await store.upsert(language: "en", word: "API", replacement: "ay-pee-eye")
        let removed = try await store.remove(language: "en", word: "API")
        #expect(removed == true)
        let all = await store.listAll()
        #expect(all["en"]?["API"] == nil)
    }

    @Test func removeMissingWordReturnsFalse() async throws {
        let store = makeStore()
        let removed = try await store.remove(language: "es", word: "nonexistent")
        #expect(removed == false)
    }

    @Test func listAllBothLanguagesPresent() async {
        let store = makeStore()
        let all = await store.listAll()
        #expect(all["es"] != nil)
        #expect(all["en"] != nil)
    }

    // MARK: - Validation

    @Test func invalidLanguageThrows() async {
        let store = makeStore()
        await #expect(throws: PronunciationStoreError.self) {
            try await store.upsert(language: "fr", word: "bonjour", replacement: "test")
        }
    }

    @Test func emptyWordThrows() async {
        let store = makeStore()
        await #expect(throws: PronunciationStoreError.self) {
            try await store.upsert(language: "es", word: "  ", replacement: "test")
        }
    }

    @Test func emptyReplacementThrows() async {
        let store = makeStore()
        await #expect(throws: PronunciationStoreError.self) {
            try await store.upsert(language: "es", word: "word", replacement: "")
        }
    }

    // MARK: - apply

    @Test func applyEscapesPlainText() async {
        let store = makeStore()
        let result = await store.apply(text: "Hello & <world>", language: "es")
        #expect(result == "Hello &amp; &lt;world&gt;")
    }

    @Test func applyReplacesKnownWord() async throws {
        let store = makeStore()
        try await store.upsert(language: "es", word: "api", replacement: "<phoneme alphabet=\"ipa\" ph=\"ˈapi\">api</phoneme>")
        let result = await store.apply(text: "The api is fast", language: "es")
        #expect(result.contains("<phoneme"))
        #expect(!result.contains("&lt;"))
    }

    @Test func applyMixedEscapeAndRaw() async throws {
        let store = makeStore()
        try await store.upsert(language: "es", word: "deploy", replacement: "<phoneme alphabet=\"ipa\" ph=\"deˈploj\">deploy</phoneme>")
        let text = "We deploy & test <often>"
        let result = await store.apply(text: text, language: "es")
        #expect(result.contains("<phoneme"))
        #expect(result.contains("&amp;"))
        #expect(result.contains("&lt;often&gt;"))
    }

    // MARK: - candidates

    @Test func candidatesForAPIinSpanishHasPhoneme() async {
        let store = makeStore()
        let cands = await store.candidates(word: "api", language: "es")
        let phonemeKinds = cands.filter { $0.kind.hasPrefix("phoneme") }
        #expect(phonemeKinds.count >= 1)
    }

    @Test func candidatesForAPIinSpanishHasDictPhoneme() async {
        let store = makeStore()
        let cands = await store.candidates(word: "api", language: "es")
        let dictCand = cands.first { $0.kind == "phoneme-dict" }
        #expect(dictCand != nil)
        #expect(dictCand?.ssml.contains("ˈapi") == true)
    }

    @Test func candidatesForEnglishWordHasRaw() async {
        let store = makeStore()
        let cands = await store.candidates(word: "hello", language: "en")
        let rawCand = cands.first { $0.kind == "raw" }
        #expect(rawCand != nil)
    }

    @Test func candidatesDeduplicatedBySSML() async {
        let store = makeStore()
        let cands = await store.candidates(word: "api", language: "es")
        let ssmlValues = cands.map { $0.ssml }
        let uniqueSSML = Set(ssmlValues)
        #expect(ssmlValues.count == uniqueSSML.count)
    }

    @Test func candidatesEmptyWordReturnsEmpty() async {
        let store = makeStore()
        let cands = await store.candidates(word: "  ", language: "es")
        #expect(cands.isEmpty)
    }

    // MARK: - candidates ordering

    @Test func candidatesAcronymInSpanishStartsWithSayAs() async {
        let store = makeStore()
        let candidates = await store.candidates(word: "API", language: "es")
        #expect(candidates.first?.kind == "say-as")
    }

    @Test func candidatesAcronymInEnglishStartsWithSayAs() async {
        let store = makeStore()
        let candidates = await store.candidates(word: "JSON", language: "en")
        #expect(candidates.first?.kind == "say-as")
    }

    // MARK: - File permissions

    @Test func upsertSetsRestrictedFilePermissions() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-perm-\(UUID()).json")
        let store = PronunciationStore(fileURL: url)
        try await store.upsert(language: "es", word: "test", replacement: "test")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attrs[.posixPermissions] as? Int == 0o600)
        try await store.upsert(language: "es", word: "test2", replacement: "test2")
        let attrs2 = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attrs2[.posixPermissions] as? Int == 0o600)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - applyEdgeSafe

    @Test func applyEdgeSafeEscapesPlainText() async {
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "hello & <world>", language: "es")
        #expect(result.contains("&amp;"))
        #expect(result.contains("&lt;"))
        #expect(result.contains("&gt;"))
        #expect(!result.contains("<say-as"))
    }

    @Test func applyEdgeSafeAcronymEmitsSpelling() async {
        // API is in the curated acronym-spellings-es.json — expect Spanish spelling, not raw letter-spacing.
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "Use the API today", language: "es")
        #expect(result.contains("éi pi ái"))
        #expect(!result.contains("A P I"))
        #expect(!result.contains("<say-as"))
        #expect(!result.contains("<phoneme"))
    }

    @Test func applyEdgeSafeAcronymPluralEmitsSpelling() async {
        // APIs → spelling "éi pi ái" + " s"
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "The APIs are slow", language: "es")
        #expect(result.contains("éi pi ái s"))
        #expect(!result.contains("A P I s"))
        #expect(!result.contains("<say-as"))
    }

    @Test func applyEdgeSafeKnownWordEmitsTransliteration() async {
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "We use framework daily", language: "es")
        let expectedTranslit = PronunciationRules.ipaToSpanishOrthography(esDict["framework"]!)
        #expect(result.contains(expectedTranslit))
        #expect(!result.contains("<say-as"))
        #expect(!result.contains("<phoneme"))
    }

    @Test func applyEdgeSafeUnknownLowercaseWordEscapesOnly() async {
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "hola mundo", language: "es")
        // "hola" and "mundo" are not in esDict, so they pass through as-is (no SSML)
        #expect(result.contains("hola"))
        #expect(result.contains("mundo"))
        #expect(!result.contains("<say-as"))
    }

    @Test func applyEdgeSafeEnglishOnlyHandlesAcronyms() async {
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "hello JSON world", language: "en")
        #expect(result.contains("J S O N"))
        #expect(!result.contains("<say-as"))
        // "hello" is not in esDict and we are in English — no transliteration
        #expect(result.contains("hello"))
        #expect(!result.contains("<phoneme"))
    }

    @Test func applyEdgeSafeIgnoresLegacyFullSSMLUserEntries() async {
        // The default seed has: "es" -> { "dónde": "<emphasis level=\"moderate\">dónde</emphasis>" }
        // This contains '<', so applyEdgeSafe must ignore it and fall through to plain escape.
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "dónde estás", language: "es")
        #expect(!result.contains("<emphasis"))
        // "dónde" should appear escaped as plain text (no special XML chars in "dónde" itself)
        #expect(result.contains("dónde"))
    }

    @Test func applyEdgeSafeUserDictWithPlainValueIsHonored() async throws {
        let store = makeStore()
        try await store.upsert(language: "es", word: "framework", replacement: "myspecial")
        let result = await store.applyEdgeSafe(text: "We use framework daily", language: "es")
        #expect(result.contains("myspecial"))
        // Should not use the IPA-based transliteration when a user override exists
        let ipaTranslit = PronunciationRules.ipaToSpanishOrthography(esDict["framework"]!)
        #expect(!result.contains(ipaTranslit))
    }

    @Test func applyEdgeSafeRespectsWordBoundaries() async {
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "frameworkers build things", language: "es")
        // "frameworkers" is not in esDict and is not an acronym — passes through unchanged
        #expect(result.contains("frameworkers"))
        let frameworkTranslit = PronunciationRules.ipaToSpanishOrthography(esDict["framework"]!)
        #expect(!result.contains(frameworkTranslit))
        #expect(!result.contains("<say-as"))
    }

    @Test func applyEdgeSafeMultipleAcronymsAndEscaping() async {
        // Both API and URL are in the curated spelling dict — expect Spanish spellings.
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "API & URL", language: "es")
        #expect(result.contains("éi pi ái"))
        #expect(result.contains("yu erre éle"))
        #expect(result.contains("&amp;"))
        #expect(!result.contains("<say-as"))
    }

    @Test func applyEdgeSafeNeverEmitsAnySSMLTags() async {
        let store = makeStore()
        // Several acronyms plus a known anglicism — output must be pure plain text (no XML tags).
        let result = await store.applyEdgeSafe(
            text: "The API and URL plus JSON and framework",
            language: "es"
        )
        #expect(!result.contains("<"))
    }

    @Test func applyEdgeSafeEmptyStringReturnsEmpty() async {
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "", language: "es")
        #expect(result == "")
    }

    @Test func applyEdgeSafeSingleCharacterPassesThrough() async {
        let store = makeStore()
        // A single letter is not an acronym (count < 2) and not in esDict — must pass through
        let result = await store.applyEdgeSafe(text: "A", language: "es")
        #expect(result == "A")
        #expect(!result.contains("<"))
    }

    @Test func applyEdgeSafeVeryLongAllCapsWordIsNotLetterSpaced() async {
        let store = makeStore()
        // 7-char all-caps token exceeds the 2–6 bound for acronyms → must pass through unchanged
        let result = await store.applyEdgeSafe(text: "ABCDEFG", language: "es")
        #expect(result.contains("ABCDEFG"))
        #expect(!result.contains("A B C D E F G"))
    }

    // MARK: - candidatesEdgeSafe

    @Test func candidatesEdgeSafeForAcronymReturnsSpellingFirst() async {
        // API is in the curated spelling dict — the first letter-spaced candidate must be the
        // Spanish spelling, with the raw letter-spacing kept as a fallback candidate.
        // No "raw" candidate for acronyms — Edge always letter-spaces them at synthesis time.
        let store = makeStore()
        let cands = await store.candidatesEdgeSafe(word: "API", language: "es")
        let letterSpacedCands = cands.filter { $0.kind == "letter-spaced" }
        #expect(letterSpacedCands.count == 2)
        #expect(letterSpacedCands[0].ssml == "éi pi ái", "curated spelling must come first")
        #expect(letterSpacedCands[1].ssml == "A P I", "raw letter-spacing kept as fallback")
        let raw = cands.first { $0.kind == "raw" }
        #expect(raw == nil, "raw candidate must be absent for acronyms — Edge always letter-spaces them")
        // No SSML tags anywhere
        for c in cands {
            #expect(!c.ssml.contains("<"))
        }
    }

    @Test func candidatesEdgeSafeForKnownAnglicismReturnsTranslit() async {
        let store = makeStore()
        let cands = await store.candidatesEdgeSafe(word: "framework", language: "es")
        let translit = cands.first { $0.kind == "translit-plain" }
        #expect(translit != nil)
        let expectedValue = PronunciationRules.ipaToSpanishOrthography(esDict["framework"]!)
        #expect(translit?.ssml == expectedValue)
        // No SSML tags
        for c in cands {
            #expect(!c.ssml.contains("<"))
        }
    }

    @Test func candidatesEdgeSafeUnknownSpanishWordReturnsRawOnly() async {
        let store = makeStore()
        let cands = await store.candidatesEdgeSafe(word: "perro", language: "es")
        #expect(cands.count == 1)
        #expect(cands.first?.kind == "raw")
        #expect(cands.first?.ssml == "perro")
    }

    @Test func candidatesEdgeSafeNeverContainsSSMLTags() async {
        let store = makeStore()
        let words = ["API", "URL", "JSON", "framework", "backend", "cache", "deploy", "hello", "perro"]
        for word in words {
            let cands = await store.candidatesEdgeSafe(word: word, language: "es")
            for c in cands {
                #expect(!c.ssml.contains("<"), "candidate '\(c.ssml)' for word '\(word)' contains '<'")
            }
        }
    }

    @Test func candidatesEdgeSafeAcronymPluralIncludesSuffix() async {
        // APIs → spelling candidate first ("éi pi ái s"), letter-spaced fallback second ("A P I s").
        let store = makeStore()
        let cands = await store.candidatesEdgeSafe(word: "APIs", language: "es")
        let letterSpacedCands = cands.filter { $0.kind == "letter-spaced" }
        #expect(letterSpacedCands.count == 2)
        #expect(letterSpacedCands[0].ssml == "éi pi ái s", "curated spelling with plural suffix must come first")
        #expect(letterSpacedCands[1].ssml == "A P I s", "raw letter-spaced plural kept as fallback")
        // No raw candidate for acronyms
        #expect(cands.first { $0.kind == "raw" } == nil)
    }

    // MARK: - acronym spelling dictionary (Phase 2)

    @Test func applyEdgeSafeAPISpellingInSpanish() async {
        // "API" is in acronym-spellings-es.json → must emit the curated Spanish spelling.
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "Hola API", language: "es")
        #expect(result.contains("éi pi ái"))
        #expect(!result.contains("A P I"))
        #expect(!result.contains("<"))
    }

    @Test func applyEdgeSafeAPIsPluralSpellingInSpanish() async {
        // "APIs" → base "API" in dict → spelling + " s".
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "Hola APIs", language: "es")
        #expect(result.contains("éi pi ái s"))
        #expect(!result.contains("A P I s"))
        #expect(!result.contains("<"))
    }

    @Test func applyEdgeSafeUnknownAcronymFallsBackToLetterSpacing() async {
        // "XYZ" is not in the spelling dict → must fall back to raw letter-spacing.
        let store = makeStore()
        let result = await store.applyEdgeSafe(text: "Use XYZ today", language: "es")
        #expect(result.contains("X Y Z"))
        #expect(!result.contains("<"))
    }

    @Test func applyEdgeSafeUserUpsertWinsOverSpellingDict() async throws {
        // User dict entry must win over the curated spelling lookup.
        let store = makeStore()
        try await store.upsert(language: "es", word: "API", replacement: "user-custom")
        let result = await store.applyEdgeSafe(text: "Hola API hoy", language: "es")
        #expect(result.contains("user-custom"))
        #expect(!result.contains("éi pi ái"))
        #expect(!result.contains("A P I"))
    }

    // MARK: - Persistence

    @Test func persistenceRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("susurro-test-\(UUID().uuidString).json")
        let store1 = PronunciationStore(fileURL: url)
        try await store1.upsert(language: "es", word: "javascript", replacement: "yabascript")

        let store2 = PronunciationStore(fileURL: url)
        let all = await store2.listAll()
        #expect(all["es"]?["javascript"] == "yabascript")
    }
}
