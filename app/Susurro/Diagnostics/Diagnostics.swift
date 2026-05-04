import Foundation

struct DiagnosticsReport: Sendable {
    let appVersion: String
    let bundleId: String
    let backendStatus: String
    let recentLogs: String
    let macOSVersion: String

    var formatted: String {
        """
        Susurro Diagnostics
        ===================
        Date:            \(ISO8601DateFormatter().string(from: Date()))
        App version:     \(appVersion)
        Bundle ID:       \(bundleId)
        macOS:           \(macOSVersion)

        TTS
        ---
        Status:          \(backendStatus)

        Recent logs (last 5 min)
        ------------------------
        \(recentLogs)
        """
    }
}

@MainActor
enum Diagnostics {
    static func collect(state: AppState) async -> DiagnosticsReport {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let backendStatus = describeBackendStatus(state.backendStatus)
        let recentLogs = await fetchRecentLogs()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        return DiagnosticsReport(
            appVersion: appVersion,
            bundleId: bundleId,
            backendStatus: backendStatus,
            recentLogs: recentLogs,
            macOSVersion: macOSVersion
        )
    }

    private static func describeBackendStatus(_ status: AppState.BackendStatus) -> String {
        switch status {
        case .starting: return "starting"
        case .ready: return "ready"
        }
    }

    private static func fetchRecentLogs() async -> String {
        await withCheckedContinuation { continuation in
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(filePath: "/usr/bin/log")
                proc.arguments = [
                    "show",
                    "--last", "5m",
                    "--info",
                    "--predicate", "subsystem == \"com.benatespina.susurro\"",
                ]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "(no output)"
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "(log command failed: \(error.localizedDescription))")
                }
            }
        }
    }
}
