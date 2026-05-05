import Foundation

/// Injects SSML break elements into a text body.
///
/// Ports `_inject_breaks` from `tts_azure.py`, applying four regex passes in order:
/// 1. U+FFFC (object replacement character) runs → 700 ms paragraph break.
/// 2. Two or more consecutive newlines (with optional whitespace) → 700 ms paragraph break.
/// 3. Single newline → 300 ms line break.
/// 4. Sentence-terminal punctuation immediately followed by an uppercase letter → 700 ms break + space.
enum BreakInjector {
    private static let paragraphBreak = "<break time=\"700ms\"/>"
    private static let lineBreak = "<break time=\"300ms\"/>"

    // Rule 1: U+FFFC runs
    private static let ruleFFFC = try! NSRegularExpression(
        pattern: "\u{FFFC}+",
        options: []
    )
    // Rule 2: Two or more newlines (possibly separated by spaces/tabs)
    private static let ruleParagraph = try! NSRegularExpression(
        pattern: "(\r?\n[ \t]*){2,}",
        options: []
    )
    // Rule 3: Single newline
    private static let ruleLine = try! NSRegularExpression(
        pattern: "\r?\n",
        options: []
    )
    // Rule 4: Sentence-terminal punctuation followed by uppercase letter
    private static let ruleSentence = try! NSRegularExpression(
        pattern: "([.!?])([A-Z\u{C1}\u{C9}\u{CD}\u{D3}\u{DA}\u{D1}])",
        options: []
    )

    static func inject(_ s: String) -> String {
        let fullRange = NSRange(s.startIndex..., in: s)

        let step1 = ruleFFFC.stringByReplacingMatches(
            in: s, options: [], range: fullRange, withTemplate: paragraphBreak
        )

        let range1 = NSRange(step1.startIndex..., in: step1)
        let step2 = ruleParagraph.stringByReplacingMatches(
            in: step1, options: [], range: range1, withTemplate: paragraphBreak
        )

        let range2 = NSRange(step2.startIndex..., in: step2)
        let step3 = ruleLine.stringByReplacingMatches(
            in: step2, options: [], range: range2, withTemplate: lineBreak
        )

        let range3 = NSRange(step3.startIndex..., in: step3)
        let step4 = ruleSentence.stringByReplacingMatches(
            in: step3, options: [], range: range3,
            withTemplate: "$1\(paragraphBreak) $2"
        )

        return step4
    }
}
