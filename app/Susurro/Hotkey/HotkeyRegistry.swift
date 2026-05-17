import Carbon.HIToolbox

// MARK: - Carbon callback (top-level, @convention(c) compatible)

private let hotkeyCallback: EventHandlerUPP = { _, eventRef, _ in
    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let capturedID = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            HotkeyRegistry.shared.handle(id: capturedID)
        }
    }
    return noErr
}

// MARK: - HotkeyRegistry

/// Multi-slot hotkey registry. Each registration has its own `EventHotKeyRef`.
/// A single shared Carbon `EventHandlerRef` demultiplexes by `EventHotKeyID.id`.
@MainActor
final class HotkeyRegistry {
    static let shared = HotkeyRegistry()

    // MARK: - Internal types

    private struct Entry {
        let id: EventHotKeyID
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    // MARK: - State

    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    // Whether to skip Carbon API calls (used in tests).
    private let skipCarbon: Bool

    // MARK: - Init

    private init() {
        self.skipCarbon = false
    }

    #if DEBUG
    /// Test-only initialiser that skips all Carbon calls but maintains bookkeeping.
    init(skipCarbon: Bool) {
        self.skipCarbon = skipCarbon
    }

    /// Exposes the running ID counter for test assertions.
    var _idCount: UInt32 { nextID }
    #endif

    // MARK: - Public API

    /// Registers a global hotkey. Replaces any existing registration for `id`.
    func register(id: String, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        // Unregister previous entry for this key, if any.
        unregister(id: id)

        installEventHandlerIfNeeded()

        let hotkeyID = EventHotKeyID(signature: 0x53757348 /* 'SusH' */, id: nextID)
        let assignedID = nextID
        nextID += 1

        if skipCarbon {
            // Bookkeeping only — no Carbon calls in test mode.
            // We cannot create a real EventHotKeyRef without Carbon, so we store
            // a sentinel. Use a bit-pattern cast via a dummy UnsafeMutableRawPointer.
            // Since we never call UnregisterEventHotKey in skipCarbon mode this is safe.
            let fakeRef: EventHotKeyRef = unsafeBitCast(
                UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1),
                to: EventHotKeyRef.self
            )
            let entry = Entry(id: hotkeyID, ref: fakeRef, handler: handler)
            entries[id] = entry
            idToKey[assignedID] = id
            AppLogger.app.debug("HotkeyRegistry (dry-run): registered id=\(id, privacy: .public) hotkeyID=\(assignedID, privacy: .public)")
            return
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        AppLogger.app.info("HotkeyRegistry: RegisterEventHotKey id=\(id, privacy: .public) status=\(status, privacy: .public) keyCode=\(keyCode, privacy: .public) modifiers=\(modifiers, privacy: .public)")

        guard status == noErr, let ref else {
            AppLogger.app.error("HotkeyRegistry: failed to register hotkey id=\(id, privacy: .public) status=\(status, privacy: .public)")
            return
        }

        let entry = Entry(id: hotkeyID, ref: ref, handler: handler)
        entries[id] = entry
        idToKey[assignedID] = id
    }

    /// Unregisters the hotkey with the given identifier, if any.
    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        idToKey.removeValue(forKey: entry.id.id)
        if !skipCarbon {
            UnregisterEventHotKey(entry.ref)
        }
    }

    /// Unregisters all hotkeys. Call on app shutdown.
    func unregisterAll() {
        for id in Array(entries.keys) {
            unregister(id: id)
        }
    }

    // MARK: - Internal: dispatch (called from the Carbon callback)

    func handle(id: UInt32) {
        guard let key = idToKey[id], let entry = entries[key] else { return }
        entry.handler()
    }

    // MARK: - Private

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, !skipCarbon else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &spec,
            nil,
            &eventHandler
        )
        AppLogger.app.info("HotkeyRegistry: InstallEventHandler status=\(status, privacy: .public)")
    }
}
