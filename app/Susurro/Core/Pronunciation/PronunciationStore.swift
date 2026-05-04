import Foundation

actor PronunciationStore {

    static let shared = PronunciationStore()

    private let fileURL: URL
    private var data: [String: [String: String]]?

    private static let defaultFileURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Susurro/pronunciations.json")
    }()

    private static let defaultSeed: [String: [String: String]] = [
        "es": ["dónde": "<emphasis level=\"moderate\">dónde</emphasis>"],
        "en": [:],
    ]

    private static let supportedLanguages: Set<String> = ["es", "en"]

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private init() {
        self.fileURL = PronunciationStore.defaultFileURL
    }

    // MARK: - Cache access

    private func loadedData() throws -> [String: [String: String]] {
        if let cached = data { return cached }
        let loaded = try readFromDisk()
        data = loaded
        return loaded
    }

    // MARK: - Public API

    func listAll() async -> [String: [String: String]] {
        guard let store = try? loadedData() else {
            return ["es": [:], "en": [:]]
        }
        var result: [String: [String: String]] = [:]
        for lang in PronunciationStore.supportedLanguages {
            result[lang] = store[lang] ?? [:]
        }
        return result
    }

    func upsert(language: String, word: String, replacement: String) async throws {
        guard PronunciationStore.supportedLanguages.contains(language) else {
            throw PronunciationStoreError.unsupportedLanguage(language)
        }
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else {
            throw PronunciationStoreError.emptyWord
        }
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReplacement.isEmpty else {
            throw PronunciationStoreError.emptyReplacement
        }
        var store = (try? loadedData()) ?? ["es": [:], "en": [:]]
        var section = store[language] ?? [:]
        section[trimmedWord] = trimmedReplacement
        store[language] = section
        data = store
        try writeToDisk(store)
    }

    func remove(language: String, word: String) async throws -> Bool {
        guard PronunciationStore.supportedLanguages.contains(language) else { return false }
        guard var store = try? loadedData(),
              var section = store[language],
              section[word] != nil else { return false }
        section.removeValue(forKey: word)
        store[language] = section
        data = store
        try writeToDisk(store)
        return true
    }

    func apply(text: String, language: String) async -> String {
        guard let store = try? loadedData(),
              let section = store[language], !section.isEmpty else {
            return SSMLEscape.escape(text)
        }

        guard let pattern = compilePattern(Array(section.keys)) else {
            return SSMLEscape.escape(text)
        }

        let ciMap: [String: String] = Dictionary(
            uniqueKeysWithValues: section.map { (k, v) in (k.lowercased(), v) }
        )

        var parts: [String] = []
        var lastEnd = text.startIndex
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for match in pattern.matches(in: text, range: fullRange) {
            guard let matchRange = Range(match.range, in: text),
                  let group1Range = Range(match.range(at: 1), in: text) else { continue }
            parts.append(SSMLEscape.escape(String(text[lastEnd ..< matchRange.lowerBound])))
            let matched = String(text[group1Range])
            if let replacement = ciMap[matched.lowercased()] {
                parts.append(replacement)
            } else {
                parts.append(SSMLEscape.escape(matched))
            }
            lastEnd = matchRange.upperBound
        }
        parts.append(SSMLEscape.escape(String(text[lastEnd...])))
        return parts.joined()
    }

    func candidates(word: String, language: String) async -> [PronunciationCandidate] {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var out: [PronunciationCandidate] = []
        let safeWord = SSMLEscape.escape(trimmed)

        if language == "es" {
            // 1. Say-as for acronyms (first, matching Python candidates() order)
            if isAcronym(trimmed) {
                out.append(PronunciationCandidate(
                    kind: "say-as",
                    label: "Read letter by letter",
                    ssml: "<say-as interpret-as=\"characters\">\(safeWord)</say-as>"
                ))
            }

            // 2. Dictionary IPA
            var seenIPAs: Set<String> = []
            if let ipa = lookupIPA(word: trimmed, language: "es") {
                seenIPAs.insert(ipa)
                let quotedIPA = SSMLEscape.quoteAttr(ipa)
                out.append(PronunciationCandidate(
                    kind: "phoneme-dict",
                    label: "IPA (curated): \(ipa)",
                    ssml: "<phoneme alphabet=\"ipa\" ph=\(quotedIPA)>\(safeWord)</phoneme>"
                ))
            }

            // 3. Derived IPA
            let derivedIPA = PronunciationRules.enToIPAEs(trimmed)
            if !derivedIPA.isEmpty && !seenIPAs.contains(derivedIPA) {
                seenIPAs.insert(derivedIPA)
                let quotedDerived = SSMLEscape.quoteAttr(derivedIPA)
                out.append(PronunciationCandidate(
                    kind: "phoneme-derived",
                    label: "IPA (derived): \(derivedIPA)",
                    ssml: "<phoneme alphabet=\"ipa\" ph=\(quotedDerived)>\(safeWord)</phoneme>"
                ))
            }

            // 4. Transliteration
            let translit = PronunciationRules.transliterateToEs(trimmed)
            if !translit.isEmpty && translit != trimmed.lowercased() {
                let quotedTranslit = SSMLEscape.quoteAttr(translit)
                out.append(PronunciationCandidate(
                    kind: "sub",
                    label: "Read as \u{201C}\(translit)\u{201D}",
                    ssml: "<sub alias=\(quotedTranslit)>\(safeWord)</sub>"
                ))
            }

            // 5. Lang switch (always)
            out.append(PronunciationCandidate(
                kind: "lang",
                label: "Read in English",
                ssml: "<lang xml:lang=\"en-US\">\(safeWord)</lang>"
            ))
        } else if language == "en" {
            // 1. Say-as for acronyms (first, matching Python candidates() order)
            if isAcronym(trimmed) {
                out.append(PronunciationCandidate(
                    kind: "say-as",
                    label: "Read letter by letter",
                    ssml: "<say-as interpret-as=\"characters\">\(safeWord)</say-as>"
                ))
            }

            // 2. Raw (always)
            out.append(PronunciationCandidate(
                kind: "raw",
                label: "Keep as-is",
                ssml: safeWord
            ))
        }

        // Dedup by ssml, preserving order
        var seen: Set<String> = []
        return out.filter { seen.insert($0.ssml).inserted }
    }

    // MARK: - Persistence

    private func readFromDisk() throws -> [String: [String: String]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let seed = PronunciationStore.defaultSeed
            try writeToDisk(seed)
            return seed
        }
        do {
            let raw = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([String: [String: String]].self, from: raw)
            return decoded
        } catch {
            return ["es": [:], "en": [:]]
        }
    }

    private func writeToDisk(_ store: [String: [String: String]]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(store)

        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmpURL = dir.appendingPathComponent(UUID().uuidString + ".tmp")
        try jsonData.write(to: tmpURL, options: .atomic)

        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
    }

    private func compilePattern(_ words: [String]) -> NSRegularExpression? {
        let keys = words.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !keys.isEmpty else { return nil }
        let alternation = keys
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?<![\\w])(\(alternation))(?![\\w])"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

enum PronunciationStoreError: Error, Sendable {
    case unsupportedLanguage(String)
    case emptyWord
    case emptyReplacement
}
