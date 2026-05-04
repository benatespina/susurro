import Foundation
import Combine

extension Notification.Name {
    static let susurroProviderWillSwap = Notification.Name("susurro.providerWillSwap")
}

@MainActor
final class TTSProviderRegistry: ObservableObject {
    static let shared = TTSProviderRegistry()

    @Published private(set) var current: any TTSProvider
    @Published private(set) var isReady: Bool = false
    @Published private(set) var azureConfigurationRequired: Bool = false

    private let makeEdge: @MainActor () -> any TTSProvider
    private let makeAzure: @MainActor () -> any TTSProvider
    private let keyProvider: @Sendable () -> String?
    private let regionProvider: @Sendable () -> String?

    /// Production singleton — reads Keychain and UserDefaults for Azure credentials.
    convenience init() {
        self.init(
            makeEdge: { EdgeTTSProvider() },
            makeAzure: {
                AzureTTSProvider(
                    keyProvider: { Keychain.string(for: "tts.azure.key") },
                    regionProvider: {
                        UserDefaults.standard.string(forKey: "tts.azure.region") ?? ""
                    }
                )
            },
            keyProvider: { Keychain.string(for: "tts.azure.key") },
            regionProvider: {
                UserDefaults.standard.string(forKey: "tts.azure.region") ?? ""
            }
        )
    }

    /// Dependency-injection initializer for tests.
    init(
        initialKind: TTSProviderKind = .edge,
        makeEdge: @escaping @MainActor () -> any TTSProvider,
        makeAzure: @escaping @MainActor () -> any TTSProvider,
        keyProvider: @escaping @Sendable () -> String?,
        regionProvider: @escaping @Sendable () -> String?
    ) {
        self.makeEdge = makeEdge
        self.makeAzure = makeAzure
        self.keyProvider = keyProvider
        self.regionProvider = regionProvider
        self.current = makeEdge()
    }

    /// Warms up the current provider; on `.azureNotConfigured` falls back to Edge.
    func warmup() async {
        do {
            try await current.warmup()
            isReady = true
        } catch BackendError.azureNotConfigured {
            azureConfigurationRequired = true
            await swap(to: .edge)
        } catch {
            AppLogger.app.error("TTSProviderRegistry warmup failed: \(error, privacy: .public)")
            isReady = false
        }
    }

    /// Swaps the active provider. Posts `.susurroProviderWillSwap` before the swap.
    func swap(to kind: TTSProviderKind) async {
        NotificationCenter.default.post(name: .susurroProviderWillSwap, object: nil)

        // For Azure: verify credentials before constructing the provider.
        if kind == .azure {
            guard let key = keyProvider(), !key.isEmpty,
                  let region = regionProvider(), !region.isEmpty else {
                azureConfigurationRequired = true
                await warmupEdgeFallback()
                return
            }
        }

        let newProvider: any TTSProvider = kind == .azure ? makeAzure() : makeEdge()

        do {
            try await newProvider.warmup()
            current = newProvider
            isReady = true
            if kind != .azure {
                azureConfigurationRequired = false
            }
        } catch BackendError.azureNotConfigured {
            azureConfigurationRequired = true
            await warmupEdgeFallback()
        } catch {
            AppLogger.app.error("TTSProviderRegistry swap to \(kind.rawValue, privacy: .public) failed: \(error, privacy: .public)")
            isReady = false
        }
    }

    // MARK: - Private

    private func warmupEdgeFallback() async {
        let edgeProvider = makeEdge()
        current = edgeProvider
        do {
            try await edgeProvider.warmup()
            isReady = true
        } catch {
            AppLogger.app.error("TTSProviderRegistry edge fallback warmup failed: \(error, privacy: .public)")
            isReady = false
        }
    }
}
