import Foundation

// MARK: - esDict

/// Spanish anglicism IPA dictionary.
/// Loaded once at process start from the bundled `anglicisms-es.json` resource.
/// An optional user overlay at `~/Library/Application Support/Susurro/anglicisms-es.json`
/// is merged on top — user-provided values win for matching keys, new keys are added.
/// Editing the overlay requires an app restart (static let caches the result).
let esDict: [String: String] = PronunciationDictLoader.load()

// MARK: - Loader

enum PronunciationDictLoader {

    // MARK: Public

    static func load() -> [String: String] {
        let bundle = loadBundle()
        guard let bundle else {
            // Safety net: bundle resource not found (shouldn't happen in production;
            // could occur in isolated unit-test runs without proper bundle setup).
            // Fall back to a small inline subset so the app is still partially functional.
            print("[PronunciationDict] WARNING: anglicisms-es.json not found in bundle — using embedded fallback")
            return fallback
        }
        let overlay = loadOverlay()
        return merge(base: bundle, overlay: overlay)
    }

    /// Merge `overlay` entries on top of `base`.
    /// Exposed as a static helper so tests can verify merge semantics independently.
    static func merge(base: [String: String], overlay: [String: String]) -> [String: String] {
        var result = base
        for (key, value) in overlay {
            result[key] = value
        }
        return result
    }

    // MARK: Private

    private static func loadBundle() -> [String: String]? {
        // Prefer the main bundle (works for app + hosted test targets).
        // Fall back to the bundle that contains this Swift file (framework/SPM scenarios).
        let candidates: [Bundle] = [.main, Bundle(for: _BundleToken.self)]
        for bundle in candidates {
            if let url = bundle.url(forResource: "anglicisms-es", withExtension: "json"),
               let dict = decodeDictionary(at: url) {
                return dict
            }
        }
        return nil
    }

    private static func loadOverlay() -> [String: String] {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first else { return [:] }
        let overlayURL = appSupport
            .appendingPathComponent("Susurro")
            .appendingPathComponent("anglicisms-es.json")
        guard FileManager.default.fileExists(atPath: overlayURL.path) else { return [:] }
        return decodeDictionary(at: overlayURL) ?? [:]
    }

    private static func decodeDictionary(at url: URL) -> [String: String]? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("[PronunciationDict] Failed to decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Safety-net fallback (≤10 entries, not the primary path)

    /// Minimal inline fallback used only when bundle loading fails.
    /// Keep in sync with the most critical entries from anglicisms-es.json.
    static let fallback: [String: String] = [
        "api": "ˈapi",
        "framework": "ˈfɾejmwoɾk",
        "backend": "bakˈend",
        "frontend": "fɾonˈtend",
        "cache": "kaʃ",
        "deploy": "deˈploj",
        "release": "ɾiˈlis",
        "commit": "koˈmit",
        "sprint": "espɾint",
        "pipeline": "ˈpajplajn",
    ]
}

// Used only to locate the correct Bundle in framework/SPM scenarios.
private final class _BundleToken {}

// MARK: - acronymSpellings

/// Per-acronym spelling dictionary for Edge TTS.
/// Loaded once at process start from the bundled `acronym-spellings-es.json` resource.
/// An optional user overlay at `~/Library/Application Support/Susurro/acronym-spellings-es.json`
/// is merged on top — user-provided values win for matching keys, new keys are added.
/// Editing the overlay requires an app restart (static let caches the result).
let acronymSpellings: [String: String] = AcronymSpellingsLoader.load()

/// Look up the Spanish-orthography spelling for a given acronym.
/// The lookup is case-insensitive (the key is always stored uppercased).
/// Returns `nil` when the acronym is not in the dictionary.
func lookupAcronymSpelling(_ acronym: String) -> String? {
    acronymSpellings[acronym.uppercased()]
}

// MARK: - AcronymSpellingsLoader

enum AcronymSpellingsLoader {

    // MARK: Public

    static func load() -> [String: String] {
        let bundle = loadBundle()
        guard let bundle else {
            print("[AcronymSpellings] WARNING: acronym-spellings-es.json not found in bundle — using embedded fallback")
            return fallback
        }
        let overlay = loadOverlay()
        return AcronymSpellingsLoader.merge(base: bundle, overlay: overlay)
    }

    /// Merge `overlay` entries on top of `base`.
    /// Exposed as a static helper so tests can verify merge semantics independently.
    static func merge(base: [String: String], overlay: [String: String]) -> [String: String] {
        var result = base
        for (key, value) in overlay {
            result[key] = value
        }
        return result
    }

    // MARK: Private

    private static func loadBundle() -> [String: String]? {
        let candidates: [Bundle] = [.main, Bundle(for: _AcronymBundleToken.self)]
        for bundle in candidates {
            if let url = bundle.url(forResource: "acronym-spellings-es", withExtension: "json"),
               let dict = decodeDictionary(at: url) {
                return dict
            }
        }
        return nil
    }

    private static func loadOverlay() -> [String: String] {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first else { return [:] }
        let overlayURL = appSupport
            .appendingPathComponent("Susurro")
            .appendingPathComponent("acronym-spellings-es.json")
        guard FileManager.default.fileExists(atPath: overlayURL.path) else { return [:] }
        return decodeDictionary(at: overlayURL) ?? [:]
    }

    private static func decodeDictionary(at url: URL) -> [String: String]? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("[AcronymSpellings] Failed to decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Safety-net fallback (≤10 entries, not the primary path)

    /// Minimal inline fallback used only when bundle loading fails.
    /// Keep in sync with the most critical entries from acronym-spellings-es.json.
    static let fallback: [String: String] = [
        "API": "éi pi ái",
        "URL": "yu erre éle",
        "HTML": "éich ti emé éle",
        "JSON": "yéison",
        "HTTP": "éich ti ti pi",
    ]
}

// Used only to locate the correct Bundle for the acronym spellings resource.
private final class _AcronymBundleToken {}

// MARK: - acronyms

let acronyms: Set<String> = [
    "API", "URL", "URI", "HTTP", "HTTPS", "JSON", "XML", "CSS", "HTML", "SQL",
    "REST", "JWT", "UUID", "CORS", "DNS", "SSH", "TCP", "UDP", "RAM", "ROM",
    "CPU", "GPU", "SSD", "HDD", "USB", "PDF", "PNG", "JPG", "SVG", "GIF",
    "AWS", "GCP", "IDE", "MVP", "QA", "UI", "UX", "OS", "IO", "DB",
    "CI", "CD", "TLS", "SSL", "FTP", "VPN", "LAN", "WAN", "VPC", "IAM",
    "S3", "EC2", "EKS", "RDS", "SDK", "ORM", "SPA", "SSR", "CSR", "SSG",
    "PR", "MR", "WIP", "ETA", "TBD", "FYI", "PoC", "POC", "B2B", "B2C",
]

func lookupIPA(word: String, language: String) -> String? {
    guard language == "es" else { return nil }
    return esDict[word.lowercased()]
}

func isAcronym(_ word: String) -> Bool {
    if acronyms.contains(word) { return true }
    return (2...6).contains(word.count) && word.allSatisfy { $0.isASCII && $0.isLetter && $0.isUppercase }
}

/// Returns `(base, hasSuffix)` when `word` is an all-caps acronym (2–6 letters)
/// optionally followed by a plural 's'; nil otherwise.
func isAcronymWithPluralSuffix(_ word: String) -> (base: String, hasSuffix: Bool)? {
    let chars = Array(word)
    guard chars.count >= 2 else { return nil }

    let hasSuffix = chars.last == "s" && chars.count >= 3
    let base = hasSuffix ? String(chars.dropLast()) : word

    guard (2...6).contains(base.count),
          base.allSatisfy({ $0.isASCII && $0.isLetter && $0.isUppercase }) else {
        return nil
    }

    return (base: base, hasSuffix: hasSuffix)
}
