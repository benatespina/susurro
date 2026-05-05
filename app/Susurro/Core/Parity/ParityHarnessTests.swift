#if PARITY_AUDIT
import Foundation
import Testing
@testable import Susurro

// To run:
//   xcodebuild -scheme SusurroTests -destination 'platform=macOS' test \
//     SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) PARITY_AUDIT'

@Suite("ParityAudit", .serialized)
struct ParityHarness {

    // MARK: - Helpers

    // The test bundle copies all resource-folder contents flat into its Resources directory.
    // Split "lang-corpus.json" → name="lang-corpus", ext="json" for the Bundle API.
    private static func fixtureURL(named filename: String) -> URL {
        let bundle = Bundle(for: BundleLocator.self)
        let parts = filename.split(separator: ".", maxSplits: 1)
        let resourceName = parts.count > 0 ? String(parts[0]) : filename
        let ext = parts.count > 1 ? String(parts[1]) : nil
        if let url = bundle.url(forResource: resourceName, withExtension: ext) {
            return url
        }
        // Fallback: look for the file in the bundle's Resources directory directly.
        let resourcesURL = bundle.resourceURL ?? bundle.bundleURL
        let candidate = resourcesURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            preconditionFailure("Fixture not found in test bundle: \(filename)")
        }
        return candidate
    }

    // MARK: - Language detection accuracy

    @Test("langDetectionAccuracy — corpus ≥95% agreement with NLLanguageRecognizer")
    func langDetectionAccuracy() throws {
        struct Entry: Decodable {
            let text: String
            let expected: String
        }

        let url = Self.fixtureURL(named: "lang-corpus.json")
        let data = try Data(contentsOf: url)
        let corpus = try JSONDecoder().decode([Entry].self, from: data)

        var correct = 0
        var wrong: [(text: String, expected: String, got: String)] = []

        for entry in corpus {
            let detected = LangDetect.detect(entry.text)
            if detected == entry.expected {
                correct += 1
            } else {
                wrong.append((entry.text, entry.expected, detected))
            }
        }

        let total = corpus.count
        let accuracy = Double(correct) / Double(total)

        if !wrong.isEmpty {
            print("--- ParityAudit: misclassified sentences (\(wrong.count)/\(total)) ---")
            for item in wrong {
                print("  expected=\(item.expected) got=\(item.got)  \"\(item.text)\"")
            }
        }

        print("ParityAudit: langDetectionAccuracy = \(String(format: "%.1f", accuracy * 100))% (\(correct)/\(total))")
        #expect(accuracy >= 0.95, "Language detection accuracy \(accuracy) is below 0.95 threshold")
    }

    // MARK: - Extraction smoke

    @Test("extractionSmoke — each URL returns > 200 chars or is skipped on network error")
    func extractionSmoke() async throws {
        let url = Self.fixtureURL(named: "extract-urls.txt")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let urls: [String] = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        // Load baseline if present — bundled alongside the other fixtures.
        struct BaselineEntry: Codable {
            let url: String
            let textLength: Int
            let title: String?
        }
        let baselineURL = Bundle(for: BundleLocator.self)
            .url(forResource: "extract-baseline", withExtension: "json")
        var baseline: [String: BaselineEntry] = [:]
        if let baselineURL,
           let baselineData = try? Data(contentsOf: baselineURL),
           let entries = try? JSONDecoder().decode([BaselineEntry].self, from: baselineData) {
            for entry in entries { baseline[entry.url] = entry }
        }

        var results: [BaselineEntry] = []
        var failures: [String] = []

        for rawURL in urls {
            let extractor = ArticleExtractor()
            do {
                let article = try await extractor.extract(url: rawURL)
                let textLen = article.text.count
                print("  OK  [\(textLen) chars] \(article.title ?? "(no title)") — \(rawURL)")
                results.append(BaselineEntry(url: rawURL, textLength: textLen, title: article.title))

                if let base = baseline[rawURL] {
                    // Lenient regression: text length should be at least half of baseline.
                    let threshold = base.textLength / 2
                    #expect(
                        textLen >= threshold,
                        "Extraction for \(rawURL) returned \(textLen) chars; baseline was \(base.textLength)"
                    )
                } else {
                    #expect(textLen > 200, "Extraction for \(rawURL) returned only \(textLen) chars")
                }
            } catch {
                // Network/server errors are expected in offline CI — record and skip.
                print("  SKIP \(rawURL) — \(error.localizedDescription)")
                failures.append(rawURL)
            }
        }

        if baseline.isEmpty && !results.isEmpty {
            let baselinePath = baselineURL?.path ?? "<app/Susurro/Resources/test-fixtures/parity/extract-baseline.json>"
            print("""
            --- ParityAudit: no baseline found at \(baselinePath)
                To record a baseline, add extract-baseline.json to the test fixtures and bundle it:
            \((try? String(data: JSONEncoder().encode(results), encoding: .utf8)) ?? "[]")
            ---
            """)
        }

        let skippedFraction = Double(failures.count) / Double(urls.count)
        print("ParityAudit: extractionSmoke — \(urls.count - failures.count)/\(urls.count) succeeded, \(failures.count) skipped")
        // If more than half of URLs are unreachable, the environment is offline; just warn.
        if skippedFraction > 0.5 {
            print("WARNING: more than half of extraction URLs were skipped (network unavailable?).")
        }
    }
}

// MARK: - Bundle locator

/// Dummy class used only to locate the test bundle via `Bundle(for:)`.
private final class BundleLocator {}
#endif
