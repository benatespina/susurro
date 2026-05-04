import Foundation

enum Chunker {
    static let maxChars = 350

    static func chunk(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sentencePattern = try! NSRegularExpression(pattern: "(?<=[.!?…])\\s+")
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        var sentences: [String] = []
        var lastEnd = trimmed.startIndex

        for match in sentencePattern.matches(in: trimmed, range: range) {
            let matchRange = Range(match.range, in: trimmed)!
            let sentence = String(trimmed[lastEnd ..< matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            lastEnd = matchRange.upperBound
        }
        let tail = String(trimmed[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }

        var result: [String] = []
        var buf = ""

        for sentence in sentences {
            if sentence.count > maxChars {
                if !buf.isEmpty {
                    result.append(buf)
                    buf = ""
                }
                result.append(contentsOf: splitLong(sentence))
                continue
            }
            if !buf.isEmpty && buf.count + 1 + sentence.count > maxChars {
                result.append(buf)
                buf = sentence
            } else {
                buf = buf.isEmpty ? sentence : "\(buf) \(sentence)"
            }
        }
        if !buf.isEmpty {
            result.append(buf)
        }

        return result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func splitLong(_ piece: String) -> [String] {
        guard piece.count > maxChars else { return [piece] }

        let commaPattern = try! NSRegularExpression(pattern: "(?<=[,;:])\\s+")
        let range = NSRange(piece.startIndex..., in: piece)
        var subs: [String] = []
        var lastEnd = piece.startIndex

        for match in commaPattern.matches(in: piece, range: range) {
            let matchRange = Range(match.range, in: piece)!
            let sub = String(piece[lastEnd ..< matchRange.lowerBound])
            if !sub.isEmpty { subs.append(sub) }
            lastEnd = matchRange.upperBound
        }
        let tail = String(piece[lastEnd...])
        if !tail.isEmpty { subs.append(tail) }

        var result: [String] = []
        var buf = ""

        for sub in subs {
            if sub.isEmpty { continue }
            if sub.count > maxChars {
                if !buf.isEmpty {
                    result.append(buf)
                    buf = ""
                }
                var i = sub.startIndex
                while i < sub.endIndex {
                    let end = sub.index(i, offsetBy: maxChars, limitedBy: sub.endIndex) ?? sub.endIndex
                    result.append(String(sub[i ..< end]))
                    i = end
                }
                continue
            }
            if !buf.isEmpty && buf.count + 1 + sub.count > maxChars {
                result.append(buf)
                buf = sub
            } else {
                buf = buf.isEmpty ? sub : "\(buf) \(sub)"
            }
        }
        if !buf.isEmpty {
            result.append(buf)
        }

        return result
    }
}
