import Foundation
import Observation

// TTSProviderKind enum lives in Core/TTS/TTSProviderKind.swift

@MainActor @Observable
final class TTSSettings {
    private static let providerKey = "tts.provider"
    private static let azureRegionKey = "tts.azure.region"
    private static let azureKeyAccount = "tts.azure.key"
    private static let autoReadEnabledKey = "claude.autoRead.enabled"

    /// Set to true after init so that the registry swap is only triggered post-init.
    private var isInitialized = false

    var provider: TTSProviderKind {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            guard isInitialized, oldValue != provider else { return }
            Task { @MainActor in
                await TTSProviderRegistry.shared.swap(to: provider)
            }
        }
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
        let raw = UserDefaults.standard.string(forKey: Self.providerKey) ?? TTSProviderKind.edge.rawValue
        self.provider = TTSProviderKind(rawValue: raw) ?? .edge
        let storedRegion = UserDefaults.standard.string(forKey: Self.azureRegionKey) ?? ""
        let sanitized = Self.sanitizeRegion(storedRegion)
        self.azureRegion = sanitized
        if sanitized != storedRegion {
            UserDefaults.standard.set(sanitized, forKey: Self.azureRegionKey)
        }
        self.autoReadEnabled = UserDefaults.standard.bool(forKey: Self.autoReadEnabledKey)
        self.isInitialized = true
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

}
