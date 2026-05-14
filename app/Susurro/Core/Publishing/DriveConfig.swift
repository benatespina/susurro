import Foundation

struct DriveConfig: Sendable, Equatable {
    let clientID: String
    let clientSecret: String
    let refreshToken: String?
    let accessToken: String?
    let accessTokenExpiry: Date?
    let folderID: String?
    let feedFileID: String?

    // MARK: - Keychain accounts

    enum Account {
        static let clientID = "library.drive.clientID"
        static let clientSecret = "library.drive.clientSecret"
        static let refreshToken = "library.drive.refreshToken"
        static let accessToken = "library.drive.accessToken"
        static let accessTokenExpiry = "library.drive.accessTokenExpiry"
        static let folderID = "library.drive.folderID"
        static let feedFileID = "library.drive.feedFileID"
    }

    // MARK: - Persistence

    static func load() -> DriveConfig? {
        guard
            let clientID = Keychain.string(for: Account.clientID), !clientID.isEmpty,
            let clientSecret = Keychain.string(for: Account.clientSecret), !clientSecret.isEmpty
        else { return nil }

        let expiryString = Keychain.string(for: Account.accessTokenExpiry)
        let expiry: Date? = expiryString.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }

        return DriveConfig(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: Keychain.string(for: Account.refreshToken),
            accessToken: Keychain.string(for: Account.accessToken),
            accessTokenExpiry: expiry,
            folderID: Keychain.string(for: Account.folderID),
            feedFileID: Keychain.string(for: Account.feedFileID)
        )
    }

    static func save(_ config: DriveConfig) {
        Keychain.set(config.clientID, for: Account.clientID)
        Keychain.set(config.clientSecret, for: Account.clientSecret)
        Keychain.set(config.refreshToken ?? "", for: Account.refreshToken)
        Keychain.set(config.accessToken ?? "", for: Account.accessToken)
        if let expiry = config.accessTokenExpiry {
            Keychain.set(ISO8601DateFormatter().string(from: expiry), for: Account.accessTokenExpiry)
        } else {
            Keychain.set("", for: Account.accessTokenExpiry)
        }
        Keychain.set(config.folderID ?? "", for: Account.folderID)
        Keychain.set(config.feedFileID ?? "", for: Account.feedFileID)
    }

    static func clear() {
        Keychain.set("", for: Account.clientID)
        Keychain.set("", for: Account.clientSecret)
        Keychain.set("", for: Account.refreshToken)
        Keychain.set("", for: Account.accessToken)
        Keychain.set("", for: Account.accessTokenExpiry)
        Keychain.set("", for: Account.folderID)
        Keychain.set("", for: Account.feedFileID)
    }

    // MARK: - Convenience

    var isConnected: Bool { refreshToken != nil }
    var hasFolder: Bool { folderID != nil }

    func feedURL() -> URL? {
        guard let fileID = feedFileID else { return nil }
        return URL(string: "https://drive.google.com/uc?export=download&id=\(fileID)")
    }

    static func enclosureURL(forFileID id: String) -> URL {
        URL(string: "https://drive.google.com/uc?export=download&id=\(id)")!
    }
}
