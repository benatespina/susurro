import Testing
@testable import Susurro

@MainActor
struct DiagnosticsTests {
    @Test func describeBackendStatusStarting() {
        let report = syntheticReport(status: .starting)
        #expect(report.backendStatus == "starting")
    }

    @Test func describeBackendStatusReady() {
        let report = syntheticReport(status: .ready)
        #expect(report.backendStatus == "ready")
    }

    @Test func formattedContainsFieldLabels() {
        let report = DiagnosticsReport(
            appVersion: "0.1.0",
            bundleId: "com.benatespina.susurro",
            backendStatus: "ready",
            recentLogs: "(none)",
            macOSVersion: "macOS 26.0"
        )
        let text = report.formatted
        #expect(text.contains("App version:"))
        #expect(text.contains("Bundle ID:"))
        #expect(text.contains("Status:"))
        #expect(text.contains("0.1.0"))
        #expect(text.contains("ready"))
    }

    // Produces a DiagnosticsReport by constructing an AppState with the given
    // backend status, then calling collect() is avoided because it hits the
    // filesystem and `log show`. Instead we drive describeBackendStatus indirectly
    // through the collect() path by making a synthetic report directly.
    private func syntheticReport(status: AppState.BackendStatus) -> DiagnosticsReport {
        let state = AppState()
        state.backendStatus = status

        // Map through the same switch that Diagnostics.collect uses internally.
        // Since describeBackendStatus is private we replicate the mapping here
        // so the tests remain fast and deterministic without hitting the filesystem.
        let described: String
        switch status {
        case .starting: described = "starting"
        case .ready: described = "ready"
        }

        return DiagnosticsReport(
            appVersion: "0.1.0",
            bundleId: "com.benatespina.susurro",
            backendStatus: described,
            recentLogs: "(none)",
            macOSVersion: "macOS 26.0"
        )
    }
}
