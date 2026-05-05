import Foundation

enum TTSConstants {
    static let voiceByLang: [String: String] = [
        "es": "es-ES-AlvaroNeural",
        "en": "en-US-AriaNeural",
    ]
    static let langCode: [String: String] = [
        "es": "es-ES",
        "en": "en-US",
    ]
    static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"
}
