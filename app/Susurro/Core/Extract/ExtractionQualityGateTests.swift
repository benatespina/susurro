import Testing
@testable import Susurro

@Suite("ExtractionQualityGate")
struct ExtractionQualityGateTests {

    // MARK: - Helpers

    /// Generates a string containing approximately `count` long words (>3 chars each).
    private func longWordText(_ count: Int) -> String {
        let word = "fascinating"
        return Array(repeating: word, count: count).joined(separator: " ")
    }

    // MARK: - Accept cases

    @Test("accepts real article with article container")
    func acceptsRealArticleWithArticleContainer() {
        // ≥150 long words → +3; article → +2; total = 5 ≥ 2
        let text = longWordText(160)
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "article",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result >= ExtractionQualityGate.acceptThreshold)
    }

    @Test("accepts real article with role=main container")
    func acceptsRealArticleWithRoleMainContainer() {
        // ≥150 long words → +3; main (normalised from [role=main]) → +2; total = 5 ≥ 2
        let text = longWordText(150)
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "main",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result >= ExtractionQualityGate.acceptThreshold)
    }

    @Test("accepts real article with body container when word count is very high")
    func acceptsRealArticleWithBodyContainerWhenWordCountHigh() {
        // ≥250 long words → +4; body → −2; total = 2 ≥ acceptThreshold.
        let text = longWordText(260)
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result >= ExtractionQualityGate.acceptThreshold)
    }

    @Test("body container with mid word count still rejected")
    func bodyContainerWithMidWordCountStillRejected() {
        // ≥150 but <250 long words → +3; body → −2; total = 1 < acceptThreshold.
        // Documents that mid-content body pages correctly fall through to tier-2.
        let text = longWordText(150)
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result < ExtractionQualityGate.acceptThreshold)
    }

    // MARK: - Reject cases

    @Test("rejects English consent banner")
    func rejectsEnglishConsentBanner() {
        // 3+ EN consent phrases → −4; body → −2; low words → −2; total = very negative
        let text = """
        We use cookies on this website. Accept cookies to continue browsing. \
        Read our cookie policy and privacy policy. We also use essential cookies \
        and personalised ads. Manage preferences to control your settings.
        """
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result < ExtractionQualityGate.acceptThreshold)
    }

    @Test("rejects Spanish consent banner")
    func rejectsSpanishConsentBanner() {
        // 3+ ES consent phrases → −4; body → −2
        let text = """
        Usamos cookies para mejorar tu experiencia. Puedes aceptar cookies o \
        gestionar preferencias. Consulta nuestra política de privacidad y \
        política de cookies. También utilizamos publicidad con interés legítimo.
        """
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result < ExtractionQualityGate.acceptThreshold)
    }

    @Test("rejects German consent banner")
    func rejectsGermanConsentBanner() {
        // 3+ DE consent phrases → −4; body → −2
        let text = """
        Wir verwenden Cookies. Cookies akzeptieren und weiter surfen. \
        Bitte lesen Sie unsere Datenschutzerklärung. Wir nutzen auch \
        Dienste mit berechtigtem Interesse gemäß DSGVO.
        """
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result < ExtractionQualityGate.acceptThreshold)
    }

    @Test("rejects link-list page with high link density and body container")
    func rejectsLinkListPage() {
        // Link density > 0.5 → −2; body → −2; word count < 30 → −2; total = very negative
        let text = "More links here today"
        let totalLength = text.count
        let linkLength = totalLength // all text is anchor text → density = 1.0
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: linkLength,
            totalTextLength: totalLength
        )
        #expect(result < ExtractionQualityGate.acceptThreshold)
    }

    @Test("rejects body container with very low word count")
    func rejectsBodyContainerWithLowWordCount() {
        // < 30 long words → −2; body → −2; total = −4
        let text = "Short text."
        let result = ExtractionQualityGate.score(
            text: text,
            containerTag: "body",
            linkTextLength: 0,
            totalTextLength: text.count
        )
        #expect(result < ExtractionQualityGate.acceptThreshold)
    }

    // MARK: - tokenizeLongWords

    @Test("tokenizeLongWords counts Unicode words with diacritics correctly")
    func tokenizeLongWordsCountsUnicodeCorrectly() {
        // "Niño" (4 chars) > 3 ✓
        // "está" (4 chars) > 3 ✓
        // "leyendo" (7 chars) > 3 ✓
        // "artículos" (9 chars) > 3 ✓
        // "cortos" (6 chars) > 3 ✓
        // All 5 words are > 3 characters → count = 5
        let text = "Niño está leyendo artículos cortos"
        let count = ExtractionQualityGate.tokenizeLongWords(text)
        #expect(count == 5)
    }
}
