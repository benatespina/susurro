import Foundation
import Observation

@MainActor @Observable
final class LibrarySettings {
    private static let ttlKey = "library.ttl.days"
    private static let autoPublishKey = "library.autoPublish"

    var playedTTLDays: Int {
        didSet { UserDefaults.standard.set(playedTTLDays, forKey: Self.ttlKey) }
    }

    var autoPublishOnSynthesize: Bool {
        didSet { UserDefaults.standard.set(autoPublishOnSynthesize, forKey: Self.autoPublishKey) }
    }

    init() {
        let d = UserDefaults.standard
        self.playedTTLDays = (d.object(forKey: Self.ttlKey) as? Int) ?? 30
        self.autoPublishOnSynthesize = (d.object(forKey: Self.autoPublishKey) as? Bool) ?? true
    }
}
