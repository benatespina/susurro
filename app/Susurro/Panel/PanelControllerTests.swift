import Testing
import AppKit
@testable import Susurro

@Suite("PanelController")
@MainActor
struct PanelControllerTests {
    @Test("hide is invoked when observer emits .rebuilding")
    func hideOnRebuilding() async {
        let observer = SelectionObserver()
        let appState = AppState()
        let controller = PanelController(observer: observer, appState: appState)

        var hideCallCount = 0
        controller.onHide = { hideCallCount += 1 }

        // Let init's rebuild settle and the observation Task register its continuation
        try? await Task.sleep(for: .milliseconds(100))

        observer.rebuild(forPid: ProcessInfo.processInfo.processIdentifier)

        // Allow the async observation loop to receive and process the event
        try? await Task.sleep(for: .milliseconds(50))

        #expect(hideCallCount >= 1)
    }
}
