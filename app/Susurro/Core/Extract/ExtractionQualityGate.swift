import Foundation

enum ExtractionQualityGate: Sendable {

    static let acceptThreshold = 2

    // Multilingual consent / cookie-banner phrases (all lowercase).
    static let consentPhrases: [String] = [
        // EN
        "accept cookies",
        "we use cookies",
        "cookie policy",
        "privacy policy",
        "manage preferences",
        "manage your preferences",
        "by clicking accept",
        "personalised ads",
        "personalized ads",
        "legitimate interest",
        "essential cookies",
        // ES
        "aceptar cookies",
        "uso de cookies",
        "política de privacidad",
        "política de cookies",
        "gestionar preferencias",
        "interés legítimo",
        // DE
        "cookies akzeptieren",
        "akzeptieren und weiter",
        "datenschutzerklärung",
        "berechtigtes interesse",
        // FR
        "accepter les cookies",
        "politique de confidentialité",
        "gérer mes choix",
        // IT
        "accetta i cookie",
        "informativa sulla privacy",
    ]

    /// Returns the number of word-like runs longer than 3 characters, using
    /// Unicode word-boundary enumeration so diacritics are handled correctly.
    static func tokenizeLongWords(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring, word.count > 3 {
                count += 1
            }
        }
        return count
    }

    /// Computes a composite quality score for a candidate extraction result.
    ///
    /// - Parameters:
    ///   - text: The extracted text.
    ///   - containerTag: Lowercased tag name of the container element (e.g. `"article"`, `"main"`, `"body"`).
    ///   - linkTextLength: Total character count of anchor text inside the container.
    ///   - totalTextLength: `text.count` of the final extracted text.
    /// - Returns: An integer score. A result is accepted when `score >= acceptThreshold`.
    static func score(
        text: String,
        containerTag: String?,
        linkTextLength: Int,
        totalTextLength: Int
    ) -> Int {
        var score = 0

        // --- Word-count signal ---
        let wordCount = tokenizeLongWords(text)
        if wordCount >= 250 {
            // Extra tier so a body-fallback container (−2) still clears the accept threshold.
            score += 4
        } else if wordCount >= 150 {
            score += 3
        } else if wordCount >= 80 {
            score += 1
        } else if wordCount < 30 {
            score -= 2
        }

        // --- Container-tag signal ---
        let tag = containerTag ?? ""
        switch tag {
        case "article", "main":
            score += 2
        case _ where tag.hasPrefix("[role") || tag == "[role=main]":
            // [role=main] selector passed through as the tag string
            score += 2
        case "body":
            score -= 2
        default:
            break
        }

        // --- Consent-boilerplate signal ---
        let lower = text.lowercased()
        let matchCount = consentPhrases.filter { lower.contains($0) }.count
        if matchCount >= 2 {
            score -= 4
        }

        // --- Link-density signal ---
        if totalTextLength > 0 {
            let density = Double(linkTextLength) / Double(totalTextLength)
            if density > 0.5 {
                score -= 2
            }
        }

        return score
    }
}
