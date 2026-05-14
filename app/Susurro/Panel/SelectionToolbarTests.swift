import Testing
@testable import Susurro

@Suite("SelectionToolbar")
@MainActor
struct SelectionToolbarTests {
    @Test("can be instantiated with onRead, onStop and onSave callbacks")
    func instantiation() {
        let appState = AppState()
        let toolbar = SelectionToolbar(
            appState: appState,
            onRead: {},
            onStop: {},
            onSave: {}
        )
        // Construction succeeds — just verify the view exists without crashing.
        _ = toolbar
    }

    @Test("invokeAction calls onRead when not playing")
    func actionCallsOnReadWhenNotPlaying() {
        let appState = AppState()
        appState.isPlaying = false

        var readCalled = false
        var stopCalled = false

        let toolbar = SelectionToolbar(
            appState: appState,
            onRead: { readCalled = true },
            onStop: { stopCalled = true },
            onSave: {}
        )

        toolbar.invokeAction()

        #expect(readCalled == true)
        #expect(stopCalled == false)
    }

    @Test("invokeAction calls onStop when playing")
    func actionCallsOnStopWhenPlaying() {
        let appState = AppState()
        appState.isPlaying = true

        var readCalled = false
        var stopCalled = false

        let toolbar = SelectionToolbar(
            appState: appState,
            onRead: { readCalled = true },
            onStop: { stopCalled = true },
            onSave: {}
        )

        toolbar.invokeAction()

        #expect(readCalled == false)
        #expect(stopCalled == true)
    }
}
