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
