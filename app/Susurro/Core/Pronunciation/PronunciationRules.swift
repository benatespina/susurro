import Foundation

enum PronunciationRules {

    private static let ipaRules: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            ("sh", "ʃ"),
            ("ch", "tʃ"),
            ("th", "θ"),
            ("ph", "f"),
            ("ck", "k"),
            ("qu", "kw"),
            ("ee", "i"),
            ("oo", "u"),
            ("ea", "i"),
            ("ai", "ej"),
            ("ay", "ej"),
            ("ou", "aw"),
            ("ow", "aw"),
            ("oa", "ow"),
            ("oi", "oj"),
            ("oy", "oj"),
            ("ie", "aj"),
            ("x", "ks"),
            ("y([aeiou])", "j$1"),
            ("y$", "i"),
            ("j", "ʃ"),
            ("v", "b"),
            ("z", "s"),
            ("w", "w"),
            ("er$", "eɾ"),
            ("ing$", "iŋ"),
            ("tion$", "ʃon"),
            ("sion$", "ʃon"),
            ("ll", "l"),
        ]
        return patterns.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    private static let translitRules: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            ("sh", "sh"),
            ("ch", "ch"),
            ("th", "z"),
            ("ph", "f"),
            ("ck", "k"),
            ("qu", "ku"),
            ("ee", "i"),
            ("oo", "u"),
            ("ea", "i"),
            ("ai", "ei"),
            ("ay", "ei"),
            ("ou", "au"),
            ("ow", "au"),
            ("oa", "ou"),
            ("oi", "oi"),
            ("oy", "oi"),
            ("ie", "ai"),
            ("x", "ks"),
            ("y([aeiou])", "y$1"),
            ("y$", "i"),
            ("j", "y"),
            ("v", "b"),
            ("z", "s"),
            ("w", "u"),
            ("er$", "er"),
            ("ing$", "in"),
            ("tion$", "shon"),
            ("sion$", "shon"),
            ("ll", "l"),
        ]
        return patterns.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    private static let ipaVowels: Set<Character> = Set("aeiouɑɛɪɔʊ")
    private static let asciiVowels: Set<Character> = Set("aeiou")

    static func enToIPAEs(_ word: String) -> String {
        var out = word.lowercased()
        for (regex, replacement) in ipaRules {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: replacement)
        }
        if let first = out.first, first == "s", out.count > 1 {
            let second = out[out.index(after: out.startIndex)]
            if !ipaVowels.contains(second) {
                out = "e" + out
            }
        }
        return out
    }

    static func transliterateToEs(_ word: String) -> String {
        var out = word.lowercased()
        for (regex, replacement) in translitRules {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: replacement)
        }
        if let first = out.first, first == "s", out.count > 1 {
            let second = out[out.index(after: out.startIndex)]
            if !asciiVowels.contains(second) {
                out = "e" + out
            }
        }
        return out
    }
}
