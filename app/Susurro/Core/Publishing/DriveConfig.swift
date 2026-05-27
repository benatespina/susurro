import Foundation

struct DriveConfig: Sendable, Equatable {
    let clientID: String
    let clientSecret: String
    let refreshToken: String?
    let accessToken: String?
    let accessTokenExpiry: Date?
    let folderID: String?
    let feedFileID: String?

    init(
        clientID: String,
        clientSecret: String,
        refreshToken: String?,
        accessToken: String?,
        accessTokenExpiry: Date?,
        folderID: String?,
        feedFileID: String?
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.accessTokenExpiry = accessTokenExpiry
        self.folderID = folderID
        self.feedFileID = feedFileID
    }

    /// Name of the root folder created/looked up on Google Drive.
    static let folderName = "Susurro"

    // MARK: - Storage keys

    /// UserDefaults keys for non-sensitive identifiers.
    ///
    /// clientID and folderID live in UserDefaults rather than Keychain because the
    /// `set("") → SecItemDelete → no Add` pattern in `Keychain.set` made empty
    /// transitional saves silently wipe them, causing relaunches to lose the values.
    enum UserDefaultsKey {
        static let clientID = "library.drive.clientID"
        static let folderID = "library.drive.folderID"
    }

    /// Keychain accounts for secrets and the feed file ID.
    enum Account {
        static let clientID = "library.drive.clientID"
        static let clientSecret = "library.drive.clientSecret"
        static let refreshToken = "library.drive.refreshToken"
        static let accessToken = "library.drive.accessToken"
        static let accessTokenExpiry = "library.drive.accessTokenExpiry"
        static let folderID = "library.drive.folderID"
        static let feedFileID = "library.drive.feedFileID"
    }

    // MARK: - Injectable UserDefaults

    /// Storage suite used by `load`/`save`/`clear`. Tests may override.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    // MARK: - Persistence

    static func load() -> DriveConfig? {
        // Migrate legacy Keychain-only storage of clientID/folderID into UserDefaults
        // so older installs preserve their setup across relaunches.
        if defaults.string(forKey: UserDefaultsKey.clientID) == nil,
           let legacyClientID = Keychain.string(for: Account.clientID),
           !legacyClientID.isEmpty {
            defaults.set(legacyClientID, forKey: UserDefaultsKey.clientID)
            if let legacyFolderID = Keychain.string(for: Account.folderID), !legacyFolderID.isEmpty {
                defaults.set(legacyFolderID, forKey: UserDefaultsKey.folderID)
            }
            Keychain.set("", for: Account.clientID)
            Keychain.set("", for: Account.folderID)
        }

        guard
            let clientID = defaults.string(forKey: UserDefaultsKey.clientID),
            !clientID.isEmpty
        else { return nil }

        let clientSecret = Keychain.string(for: Account.clientSecret) ?? ""

        let expiryString = Keychain.string(for: Account.accessTokenExpiry)
        let expiry: Date? = expiryString.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }

        let folderIDRaw = defaults.string(forKey: UserDefaultsKey.folderID) ?? ""
        let folderID: String? = folderIDRaw.isEmpty ? nil : folderIDRaw

        return DriveConfig(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: Keychain.string(for: Account.refreshToken),
            accessToken: Keychain.string(for: Account.accessToken),
            accessTokenExpiry: expiry,
            folderID: folderID,
            feedFileID: Keychain.string(for: Account.feedFileID)
        )
    }

    static func save(_ config: DriveConfig) {
        defaults.set(config.clientID, forKey: UserDefaultsKey.clientID)
        if let folderID = config.folderID, !folderID.isEmpty {
            defaults.set(folderID, forKey: UserDefaultsKey.folderID)
        } else {
            defaults.removeObject(forKey: UserDefaultsKey.folderID)
        }

        Keychain.set(config.clientSecret, for: Account.clientSecret)
        Keychain.set(config.refreshToken ?? "", for: Account.refreshToken)
        Keychain.set(config.accessToken ?? "", for: Account.accessToken)
        if let expiry = config.accessTokenExpiry {
            Keychain.set(ISO8601DateFormatter().string(from: expiry), for: Account.accessTokenExpiry)
        } else {
            Keychain.set("", for: Account.accessTokenExpiry)
        }
        Keychain.set(config.feedFileID ?? "", for: Account.feedFileID)
    }

    static func clear() {
        defaults.removeObject(forKey: UserDefaultsKey.clientID)
        defaults.removeObject(forKey: UserDefaultsKey.folderID)
        Keychain.set("", for: Account.clientSecret)
        Keychain.set("", for: Account.refreshToken)
        Keychain.set("", for: Account.accessToken)
        Keychain.set("", for: Account.accessTokenExpiry)
        Keychain.set("", for: Account.feedFileID)
    }

    static func clearTokensOnly() {
        Keychain.set("", for: Account.refreshToken)
        Keychain.set("", for: Account.accessToken)
        Keychain.set("", for: Account.accessTokenExpiry)
    }

    // MARK: - Copy helpers

    func copying(
        accessToken: String? = nil,
        accessTokenExpiry: Date? = nil,
        feedFileID: String? = nil
    ) -> DriveConfig {
        DriveConfig(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken,
            accessToken: accessToken ?? self.accessToken,
            accessTokenExpiry: accessTokenExpiry ?? self.accessTokenExpiry,
            folderID: folderID,
            feedFileID: feedFileID ?? self.feedFileID
        )
    }

    /// Returns a new config with fresh OAuth tokens (and optionally a new folderID),
    /// preserving `clientID`, `clientSecret`, and `feedFileID` from the receiver.
    func copying(
        refreshToken: String?,
        accessToken: String?,
        accessTokenExpiry: Date?,
        folderID: String? = nil
    ) -> DriveConfig {
        DriveConfig(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken,
            accessToken: accessToken,
            accessTokenExpiry: accessTokenExpiry,
            folderID: folderID ?? self.folderID,
            feedFileID: self.feedFileID
        )
    }

    // MARK: - Convenience

    var isConnected: Bool { (refreshToken?.isEmpty == false) }
    var hasFolder: Bool { folderID != nil }

    func feedURL() -> URL? {
        guard let fileID = feedFileID else { return nil }
        return URL(string: "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&authuser=0&confirm=t")
    }

    static func enclosureURL(forFileID id: String) -> URL {
        URL(string: "https://drive.usercontent.google.com/download?id=\(id)&export=download&authuser=0&confirm=t")!
    }
}
