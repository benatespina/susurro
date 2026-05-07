import Foundation

struct UpdateSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastCheckDate: Date? {
        get { defaults.object(forKey: "updates.lastCheckDate") as? Date }
        set { defaults.set(newValue, forKey: "updates.lastCheckDate") }
    }
}
