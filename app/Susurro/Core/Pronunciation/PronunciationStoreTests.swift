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
