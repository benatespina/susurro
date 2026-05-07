import AppKit
import Foundation
import UserNotifications

actor ReleaseChecker {
    static let shared = ReleaseChecker()

    enum CheckOutcome: Equatable {
        case upToDate(currentVersion: String)
        case updateAvailable(ReleaseInfo)
        case skipped(reason: String)
        case failed(message: String)
    }

    struct ReleaseInfo: Equatable, Sendable {
        let tagName: String
        let normalizedVersion: String
        let htmlURL: URL
        let publishedAt: Date?
        let displayName: String
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let published_at: String?
        let name: String?
    }

    private let apiURL = URL(string: "https://api.github.com/repos/benatespina/susurro/releases/latest")!

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
    }

    // MARK: - Public API

    func checkIfDue() async {
        var settings = UpdateSettings()
        guard shouldCheckNow(now: Date(), settings: settings) else { return }
        defer { settings.lastCheckDate = Date() }

        guard let info = try? await checkLatest() else { return }
        let comparison = compareVersion(current: currentVersion, latest: info.normalizedVersion)
        guard comparison == .orderedAscending else { return }

        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let content = UNMutableNotificationContent()
        content.title = "Susurro update available"
        content.body = "Version \(info.normalizedVersion) is now available"
        content.userInfo = ["releaseURL": info.htmlURL.absoluteString]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "susurro.update.\(info.tagName)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func userTriggeredCheck() async -> CheckOutcome {
        var settings = UpdateSettings()
        settings.lastCheckDate = Date()

        do {
            let info = try await checkLatest()
            let comparison = compareVersion(current: currentVersion, latest: info.normalizedVersion)
            if comparison == .orderedAscending {
                return .updateAvailable(info)
            } else {
                return .upToDate(currentVersion: currentVersion)
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    nonisolated func shouldCheckNow(now: Date, settings: UpdateSettings) -> Bool {
        guard let last = settings.lastCheckDate else { return false }
        return now.timeIntervalSince(last) >= 86400
    }

    nonisolated func compareVersion(current: String, latest: String) -> ComparisonResult {
        func parse(_ version: String) -> [Int]? {
            let stripped = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let withoutPrerelease = stripped.split(separator: "-", maxSplits: 1).first.map(String.init) ?? stripped
            let parts = withoutPrerelease.split(separator: ".").map(String.init)
            var components: [Int] = []
            for part in parts {
                guard let n = Int(part) else { return nil }
                components.append(n)
            }
            while components.count < 3 { components.append(0) }
            return components
        }

        guard let currentParts = parse(current), let latestParts = parse(latest) else {
            return .orderedSame
        }

        for (c, l) in zip(currentParts, latestParts) {
            if c < l { return .orderedAscending }
            if c > l { return .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated func parseReleaseInfo(from data: Data) throws -> ReleaseInfo {
        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)

        guard let htmlURL = URL(string: release.html_url) else {
            throw URLError(.badURL)
        }

        let tagName = release.tag_name
        let normalizedVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        var publishedAt: Date?
        if let publishedAtString = release.published_at {
            let isoFormatter = ISO8601DateFormatter()
            publishedAt = isoFormatter.date(from: publishedAtString)
        }

        let displayName = release.name ?? tagName

        return ReleaseInfo(
            tagName: tagName,
            normalizedVersion: normalizedVersion,
            htmlURL: htmlURL,
            publishedAt: publishedAt,
            displayName: displayName
        )
    }

    // MARK: - Private

    private func checkLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.setValue("Susurro/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseReleaseInfo(from: data)
    }
}
