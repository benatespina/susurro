import Foundation
import NaturalLanguage

enum LangDetect {
    static func detect(_ text: String) -> String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else {
            return "en"
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = [.spanish: 0.5, .english: 0.5]
        recognizer.languageConstraints = [.spanish, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .spanish ? "es" : "en"
    }
}
