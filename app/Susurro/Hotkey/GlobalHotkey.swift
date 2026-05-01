import AppKit
import Carbon.HIToolbox

/// Thin wrapper around Carbon's RegisterEventHotKey for system-wide shortcuts.
/// Susurro registers a single hotkey to trigger "Read this" from any app.
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { manager.handler?() }
                }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
        AppLogger.app.info("hotkey InstallEventHandler status=\(installStatus, privacy: .public)")

        let signature: OSType = 0x53555352 // 'SUSR'
        let id = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        AppLogger.app.info("hotkey RegisterEventHotKey status=\(regStatus, privacy: .public) keyCode=\(keyCode, privacy: .public) modifiers=\(modifiers, privacy: .public) ref=\(ref != nil, privacy: .public)")
        self.hotKeyRef = ref
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            self.eventHandler = nil
        }
        self.handler = nil
    }
}

enum HotkeyDefaults {
    /// Cmd+Option+R — "Read this".
    static let readThisKeyCode: UInt32 = UInt32(kVK_ANSI_R)
    static let readThisModifiers: UInt32 = UInt32(cmdKey | optionKey)
}
