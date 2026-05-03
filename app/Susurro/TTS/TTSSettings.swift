import Foundation
import Observation

enum TTSProvider: String, CaseIterable, Sendable {
    case edge
    case azure

    var displayName: String {
        switch self {
        case .edge: "Edge (free)"
        case .azure: "Azure Speech (subscription)"
        }
    }
}

@MainActor @Observable
final class TTSSettings {
    private static let providerKey = "tts.provider"
    private static let azureRegionKey = "tts.azure.region"
    private static let azureKeyAccount = "tts.azure.key"
    private static let autoReadEnabledKey = "claude.autoRead.enabled"

    var provider: TTSProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey) }
    }

    var autoReadEnabled: Bool {
        didSet { UserDefaults.standard.set(autoReadEnabled, forKey: Self.autoReadEnabledKey) }
    }

    var azureRegion: String {
        didSet {
            let sanitized = Self.sanitizeRegion(azureRegion)
            if sanitized != azureRegion {
                azureRegion = sanitized
                return
            }
            UserDefaults.standard.set(azureRegion, forKey: Self.azureRegionKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.providerKey) ?? TTSProvider.edge.rawValue
        self.provider = TTSProvider(rawValue: raw) ?? .edge
        let storedRegion = UserDefaults.standard.string(forKey: Self.azureRegionKey) ?? ""
        let sanitized = Self.sanitizeRegion(storedRegion)
        self.azureRegion = sanitized
        if sanitized != storedRegion {
            UserDefaults.standard.set(sanitized, forKey: Self.azureRegionKey)
        }
        self.autoReadEnabled = UserDefaults.standard.bool(forKey: Self.autoReadEnabledKey)
    }

    private static func sanitizeRegion(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let firstToken = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""
        return firstToken
    }

    var azureKey: String {
        get { Keychain.string(for: Self.azureKeyAccount) ?? "" }
        set { Keychain.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.azureKeyAccount) }
    }

    var azureConfigured: Bool {
        !azureKey.isEmpty && !azureRegion.isEmpty
    }

    func envVars() -> [String: String] {
        var env: [String: String] = ["SUSURRO_TTS_PROVIDER": provider.rawValue]
        if provider == .azure {
            env["AZURE_SPEECH_KEY"] = azureKey
            env["AZURE_SPEECH_REGION"] = azureRegion
        }
        return env
    }
}
