import Testing
@testable import Susurro

// MARK: - IPA → Spanish Orthography Tests
//
// Each test takes IPA from esDict (or a synthetic fixture) and verifies the
// expected Spanish orthographic output including stressed-vowel tildes.

@Suite struct IPAToSpanishOrthographyTests {

    private func convert(_ ipa: String) -> String {
        PronunciationRules.ipaToSpanishOrthography(ipa)
    }

    // MARK: - Table examples (from spec)

    @Test func framework() {
        // ˈfɾejmwoɾk → fréimworc
        #expect(convert(esDict["framework"]!) == "fréimworc")
    }

    @Test func api() {
        // ˈapi → ápi
        #expect(convert(esDict["api"]!) == "ápi")
    }

    @Test func backend() {
        // bakˈend → bakénd
        #expect(convert(esDict["backend"]!) == "bakénd")
    }

    @Test func frontend() {
        // fɾonˈtend → fronténd
        #expect(convert(esDict["frontend"]!) == "fronténd")
    }

    @Test func endpoint() {
        // ˈendpojnt → éndpoint
        #expect(convert(esDict["endpoint"]!) == "éndpoint")
    }

    @Test func cache() {
        // kaʃ → cash  (no stress marker → no tilde)
        #expect(convert(esDict["cache"]!) == "cash")
    }

    @Test func branch() {
        // bɾantʃ → branch
        #expect(convert(esDict["branch"]!) == "branch")
    }

    @Test func commit() {
        // koˈmit → komít
        #expect(convert(esDict["commit"]!) == "komít")
    }

    @Test func release() {
        // ɾiˈlis → rilís
        #expect(convert(esDict["release"]!) == "rilís")
    }

    @Test func feature() {
        // ˈfitʃeɾ → fícher
        #expect(convert(esDict["feature"]!) == "fícher")
    }

    @Test func container() {
        // konˈtejneɾ → kontéiner
        #expect(convert(esDict["container"]!) == "kontéiner")
    }

    @Test func developer() {
        // deˈbeloper → debéloper
        #expect(convert(esDict["developer"]!) == "debéloper")
    }

    @Test func request() {
        // ɾiˈkwest → rikwést
        #expect(convert(esDict["request"]!) == "rikwést")
    }

    @Test func workflow() {
        // ˈweɾkflow → wérkflou
        #expect(convert(esDict["workflow"]!) == "wérkflou")
    }


    @Test func merge() {
        // merʃ → mersh
        #expect(convert(esDict["merge"]!) == "mersh")
    }

    // MARK: - Edge cases

    @Test func emptyInputReturnsEmpty() {
        #expect(convert("") == "")
    }

    @Test func noStressMarkerProducesNoTilde() {
        // "kaʃ" — no ˈ → output has no accented vowels
        let out = convert("kaʃ")
        let accentedVowels: Set<Character> = ["á", "é", "í", "ó", "ú"]
        #expect(!out.contains(where: { accentedVowels.contains($0) }))
    }

    @Test func tshDigraphBeforeIndividualConsonants() {
        // "tʃ" must become "ch", not "tsh"
        let out = convert("tʃ")
        #expect(out == "ch")
        #expect(!out.contains("t"))
        #expect(!out.contains("sh"))
    }

    @Test func stressedDiphthongEjBecomesEiWithAccent() {
        // ˈej → éi  (stress on diphthong first vowel)
        #expect(convert("ˈej") == "éi")
    }

    @Test func unstressedDiphthongEjBecomesEi() {
        #expect(convert("ej") == "ei")
    }

    @Test func finalKBecomesC() {
        // IPA "bak" → word-final k → "bac"
        #expect(convert("bak") == "bac")
    }

    @Test func finalRhoticBecomesR() {
        // ɾ at word end produces single r
        let out = convert("koˈmit")  // commit ends in t, not ɾ — use a word with final ɾ
        _ = out  // just ensure no crash; dedicated check below
        #expect(convert("ˈɾuteɾ") == "rúter")   // router: ˈɾuteɾ → rúter
    }

    @Test func kBeforeEStaysK() {
        // k before e → k (loanword convention, not Spanish-native 'qu')
        #expect(convert("ˈkest") == "kést")
    }

    @Test func kBeforeIStaysK() {
        // k before i → k  (loanword convention)
        #expect(convert("ˈkit") == "kít")
    }

    @Test func kBeforeABecomesC() {
        // Synthetic: "ˈkal" → "cál"
        #expect(convert("ˈkal") == "cál")
    }

    @Test func gBeforeEBecomesGu() {
        // Synthetic: "ˈɡel" → "guél"
        #expect(convert("ˈɡel") == "guél")
    }

    @Test func gBeforeABecomesG() {
        // Synthetic: "ˈɡal" → "gál"
        #expect(convert("ˈɡal") == "gál")
    }

    @Test func wProducesW() {
        // Loanword w stays as w
        #expect(convert("web") == "web")
    }

    @Test func ngProducesN() {
        // ŋ → n; no stress marker → no tilde
        #expect(convert("estɾiŋ") == "estrin")
    }

    @Test func diphthongAjBecomesAi() {
        #expect(convert("ˈaj") == "ái")
    }

    @Test func diphthongAwBecomesAu() {
        #expect(convert("ˈaw") == "áu")
    }

    @Test func diphthongOwBecomesOu() {
        #expect(convert("ˈow") == "óu")
    }

    // MARK: - Additional dict entries

    @Test func pipeline() {
        // ˈpajplajn → páiplain  (both aj diphthongs → ai; stress on first a)
        #expect(convert(esDict["pipeline"]!) == "páiplain")
    }

    @Test func deploy() {
        // deˈploj → deplói
        #expect(convert(esDict["deploy"]!) == "deplói")
    }

    @Test func router() {
        // ˈɾuteɾ → rúter
        #expect(convert(esDict["router"]!) == "rúter")
    }

    // MARK: - New anglicisms spot-checks

    @Test func reactTransliterates() {
        // ɾiˈakt → riákt
        #expect(convert(esDict["react"]!) == "riákt")
    }

    @Test func dockerTransliterates() {
        // ˈdokeɾ → dóker
        #expect(convert(esDict["docker"]!) == "dóker")
    }

    @Test func asyncTransliterates() {
        // ˈasiŋk → ásinc
        #expect(convert(esDict["async"]!) == "ásinc")
    }

    @Test func kubernetesTransliterates() {
        // kuberˈnetes → kubernétes
        #expect(convert(esDict["kubernetes"]!) == "kubernétes")
    }

    @Test func awaitTransliterates() {
        // aˈwejt → awéit
        #expect(convert(esDict["await"]!) == "awéit")
    }
}
