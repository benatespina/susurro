import Foundation

// MARK: - IPA → Spanish Orthography Converter

extension PronunciationRules {

    /// Converts an IPA string (as stored in `esDict`) to a Spanish orthographic
    /// representation, including accented vowels that mark primary stress (`ˈ`).
    ///
    /// Symbol inventory handled: b d f k l m n p r s t w ŋ ɡ ɾ ʃ tʃ a e i o u ˈ
    /// Diphthongs: ej aj oj aw ow (vowel+glide pairs)
    ///
    /// - Parameter ipa: An IPA string, e.g. `"ˈfɾejmwoɾk"`.
    /// - Returns: Spanish orthography, e.g. `"fréimworc"`.
    static func ipaToSpanishOrthography(_ ipa: String) -> String {
        guard !ipa.isEmpty else { return "" }

        var chars = Array(ipa)
        var result = ""
        var i = 0
        var stressNext = false  // true when the next vowel should receive a tilde

        while i < chars.count {
            let c = chars[i]

            // ── Stress marker ──────────────────────────────────────────────
            if c == "ˈ" {
                stressNext = true
                i += 1
                continue
            }

            // ── Two-character digraph: tʃ → ch (must precede lone t / ʃ) ──
            if c == "t", i + 1 < chars.count, chars[i + 1] == "ʃ" {
                result += "ch"
                i += 2
                continue
            }

            // ── Vowel (possibly stressed, possibly followed by a glide) ───
            if isIPAVowel(c) {
                // Look ahead for a diphthong glide (j or w)
                let nextIdx = i + 1
                let hasGlide = nextIdx < chars.count && (chars[nextIdx] == "j" || chars[nextIdx] == "w")

                if hasGlide {
                    let glide = chars[nextIdx]
                    let (v1, v2) = diphthongLetters(vowel: c, glide: glide)
                    if stressNext {
                        result += accentedVowel(v1) + v2
                        stressNext = false
                    } else {
                        result += v1 + v2
                    }
                    i += 2  // consume vowel + glide
                } else {
                    let letter = String(c)  // a/e/i/o/u are identical in Spanish
                    if stressNext {
                        result += accentedVowel(letter)
                        stressNext = false
                    } else {
                        result += letter
                    }
                    i += 1
                }
                continue
            }

            // ── Consonants ────────────────────────────────────────────────

            switch c {
            case "b": result += "b"
            case "d": result += "d"
            case "f": result += "f"
            case "k":
                // Spanish orthography convention:
                //   • word-final k → c  (e.g. ˈfɾejmwoɾk → fréimworc)
                //   • k before 'a' → c  (e.g. kaʃ → cash)
                //   • all other positions → k  (preserve loanword k)
                let nextChar = nextNonStress(chars: chars, from: i + 1)
                if nextChar == nil {
                    result += "c"       // word-final
                } else if nextChar! == "a" {
                    result += "c"       // before 'a'
                } else {
                    result += "k"       // all other contexts
                }
            case "l": result += "l"
            case "m": result += "m"
            case "n": result += "n"
            case "p": result += "p"
            case "r": result += "r"
            case "s": result += "s"
            case "t": result += "t"
            case "j":
                // Standalone j (onset glide before a vowel, e.g. kje → kie)
                // This path is reached only when j is NOT consumed as part of
                // a vowel+j diphthong (handled in the vowel branch above).
                result += "i"
            case "w": result += "w"
            case "ŋ": result += "n"   // simplified: always n
            case "ɡ":
                // g before a/o/u; gu before e/i
                let nextChar = nextNonStress(chars: chars, from: i + 1)
                if let nc = nextChar, isIPAFrontVowel(nc) {
                    result += "gu"
                } else {
                    result += "g"
                }
            case "ɾ":
                // word-final ɾ → r (same letter, single tap)
                result += "r"
            case "ʃ": result += "sh"
            default:
                // Pass through any unrecognised character unchanged
                result += String(c)
            }

            i += 1
        }

        return result
    }

    // MARK: - Private helpers

    private static let ipaVowelSet: Set<Character> = ["a", "e", "i", "o", "u"]
    private static let ipaFrontVowelSet: Set<Character> = ["e", "i"]

    private static func isIPAVowel(_ c: Character) -> Bool {
        ipaVowelSet.contains(c)
    }

    private static func isIPAFrontVowel(_ c: Character) -> Bool {
        ipaFrontVowelSet.contains(c)
    }

    /// Returns the next character in `chars` starting at `from`, skipping `ˈ`.
    private static func nextNonStress(chars: [Character], from idx: Int) -> Character? {
        var j = idx
        while j < chars.count {
            if chars[j] != "ˈ" { return chars[j] }
            j += 1
        }
        return nil
    }

    /// Returns the two orthographic letters for a vowel+glide diphthong.
    private static func diphthongLetters(vowel: Character, glide: Character) -> (String, String) {
        if glide == "j" {
            switch vowel {
            case "e": return ("e", "i")   // ej → ei
            case "a": return ("a", "i")   // aj → ai
            case "o": return ("o", "i")   // oj → oi
            default:  return (String(vowel), "i")
            }
        } else {  // glide == "w"
            switch vowel {
            case "a": return ("a", "u")   // aw → au
            case "o": return ("o", "u")   // ow → ou
            default:  return (String(vowel), "u")
            }
        }
    }

    /// Returns the accented (tilde) version of a Spanish vowel letter.
    private static func accentedVowel(_ letter: String) -> String {
        switch letter {
        case "a": return "á"
        case "e": return "é"
        case "i": return "í"
        case "o": return "ó"
        case "u": return "ú"
        default:  return letter
        }
    }
}
