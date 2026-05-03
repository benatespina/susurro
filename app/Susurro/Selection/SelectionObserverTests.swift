import Testing
import AppKit
@testable import Susurro

@Suite("SelectionObserver")
@MainActor
struct SelectionObserverTests {
    @Test("rebuild emits .rebuilding before tearing down current observer")
    func rebuildEmitsRebuilding() async {
        let observer = SelectionObserver()

        // Wait past the minimumEmitInterval (50 ms) used by the throttle,
        // and past init's own rebuild call, before subscribing.
        try? await Task.sleep(for: .milliseconds(100))

        let stream = observer.events()

        // Yield so the continuation Task can register itself on @MainActor
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))

        var received: [SelectionObserver.Event] = []
        let collectTask = Task { @MainActor in
            for await event in stream {
                received.append(event)
                if received.count >= 1 { break }
            }
        }

        // Trigger rebuild with our own pid — safe because it short-circuits before AX setup
        observer.rebuild(forPid: ProcessInfo.processInfo.processIdentifier)

        try? await Task.sleep(for: .milliseconds(30))
        collectTask.cancel()

        #expect(received.contains(.rebuilding))
    }

    // MARK: - transition() pure-helper tests

    @Test("transition returns .none when both current and lastSeen are nil")
    func transitionNilToNil() {
        #expect(SelectionObserver.transition(currentSelectionText: nil, lastSeen: nil) == .none)
    }

    @Test("transition returns .none when current is whitespace only")
    func transitionWhitespaceToNone() {
        #expect(SelectionObserver.transition(currentSelectionText: "   \n", lastSeen: nil) == .none)
    }

    @Test("transition returns .changed when lastSeen is nil and current has text")
    func transitionNilToText() {
        #expect(SelectionObserver.transition(currentSelectionText: "hello", lastSeen: nil) == .changed("hello"))
    }

    @Test("transition returns .none when current equals lastSeen (no double-emit)")
    func transitionSameText() {
        #expect(SelectionObserver.transition(currentSelectionText: "hello", lastSeen: "hello") == .none)
    }

    @Test("transition returns .changed when current differs from lastSeen")
    func transitionDifferentText() {
        #expect(SelectionObserver.transition(currentSelectionText: "world", lastSeen: "hello") == .changed("world"))
    }

    @Test("transition returns .cleared when current is nil but lastSeen had text")
    func transitionTextToNil() {
        #expect(SelectionObserver.transition(currentSelectionText: nil, lastSeen: "hello") == .cleared)
    }

    @Test("transition returns .cleared when current is empty but lastSeen had text")
    func transitionTextToEmpty() {
        #expect(SelectionObserver.transition(currentSelectionText: "", lastSeen: "hello") == .cleared)
    }

    @Test("transition returns .none when current is empty and lastSeen is already nil")
    func transitionEmptyToNil() {
        #expect(SelectionObserver.transition(currentSelectionText: "", lastSeen: nil) == .none)
    }

    // MARK: - rebuild tests

    @Test("rebuild emits .rebuilding each time it is called")
    func rebuildEmitsRebuildingEachCall() async {
        let observer = SelectionObserver()

        // Let init's rebuild settle and pass the throttle window
        try? await Task.sleep(for: .milliseconds(100))

        let stream = observer.events()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))

        var count = 0
        let collectTask = Task { @MainActor in
            for await event in stream {
                if event == .rebuilding { count += 1 }
                if count >= 2 { break }
            }
        }

        observer.rebuild(forPid: ProcessInfo.processInfo.processIdentifier)
        try? await Task.sleep(for: .milliseconds(100))
        observer.rebuild(forPid: ProcessInfo.processInfo.processIdentifier)
        try? await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()

        #expect(count >= 2)
    }
}
