import Testing
@testable import Susurro

@Suite("HotkeyRegistry")
@MainActor
struct HotkeyRegistryTests {

    // MARK: - Helpers

    /// Creates an isolated registry in dry-run mode (no Carbon side effects).
    private func makeRegistry() -> HotkeyRegistry {
        HotkeyRegistry(skipCarbon: true)
    }

    // MARK: - Tests

    @Test("registering two distinct IDs assigns distinct EventHotKeyID.id values")
    func distinctIDsGetDistinctHotkeyIDs() {
        let registry = makeRegistry()
        let before = registry._idCount

        registry.register(id: "alpha", keyCode: 0, modifiers: 0, handler: {})
        registry.register(id: "beta", keyCode: 1, modifiers: 0, handler: {})

        // Two registrations consumed two slots.
        #expect(registry._idCount == before + 2)
    }

    @Test("re-registering the same string id replaces the previous entry")
    func reRegistrationReplacesEntry() {
        let registry = makeRegistry()

        var callCount = 0
        registry.register(id: "key", keyCode: 0, modifiers: 0, handler: { callCount += 1 })

        let idAfterFirst = registry._idCount

        // Re-register with a different handler.
        var newCallCount = 0
        registry.register(id: "key", keyCode: 0, modifiers: 0, handler: { newCallCount += 1 })

        // ID counter advanced by one more slot.
        #expect(registry._idCount == idAfterFirst + 1)

        // Firing the active handler (using the new hotkeyID slot) invokes only the new handler.
        // The new slot ID is idAfterFirst (0-based: nextID before second register == idAfterFirst).
        let newSlotID = idAfterFirst // the ID assigned during the second registration
        registry.handle(id: newSlotID)

        #expect(callCount == 0)
        #expect(newCallCount == 1)
    }

    @Test("unregister removes the entry from the registry")
    func unregisterRemovesEntry() {
        let registry = makeRegistry()
        let slotID = registry._idCount  // will be assigned to "key"

        var called = false
        registry.register(id: "key", keyCode: 0, modifiers: 0, handler: { called = true })
        registry.unregister(id: "key")

        // Dispatching to the now-removed slot is a no-op.
        registry.handle(id: slotID)
        #expect(called == false)
    }

    @Test("unregisterAll clears every entry")
    func unregisterAllClearsEverything() {
        let registry = makeRegistry()
        let slot1 = registry._idCount
        let slot2 = registry._idCount + 1

        var aCalled = false
        var bCalled = false
        registry.register(id: "a", keyCode: 0, modifiers: 0, handler: { aCalled = true })
        registry.register(id: "b", keyCode: 1, modifiers: 0, handler: { bCalled = true })

        registry.unregisterAll()

        registry.handle(id: slot1)
        registry.handle(id: slot2)

        #expect(aCalled == false)
        #expect(bCalled == false)
    }

    @Test("handler fires when handle(id:) is called with the correct slot ID")
    func handleDispatchesCorrectly() {
        let registry = makeRegistry()
        let slotID = registry._idCount

        var fired = false
        registry.register(id: "test", keyCode: 0, modifiers: 0, handler: { fired = true })

        registry.handle(id: slotID)
        #expect(fired == true)
    }

    @Test("handle with unknown id is a no-op")
    func handleUnknownIDIsNoop() {
        let registry = makeRegistry()
        // Should not crash or do anything observable.
        registry.handle(id: 9999)
    }
}
