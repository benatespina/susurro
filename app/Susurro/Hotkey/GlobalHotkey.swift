import Carbon.HIToolbox

/// Canonical key-code and modifier constants for Susurro's global hotkeys.
/// All hotkeys are registered through `HotkeyRegistry`.
enum HotkeyDefaults {
    // MARK: - Read selection  (Cmd+Option+R)

    static let readSelectionID = "readSelection"
    static let readSelectionKeyCode: UInt32 = UInt32(kVK_ANSI_R)
    static let readSelectionModifiers: UInt32 = UInt32(cmdKey | optionKey)

    // Back-compat aliases (kept so any call site that used the old names still compiles).
    static let readThisKeyCode: UInt32 = readSelectionKeyCode
    static let readThisModifiers: UInt32 = readSelectionModifiers

    // MARK: - Save to reading list  (Cmd+Option+S)

    static let saveURLID = "saveURL"
    static let saveURLKeyCode: UInt32 = UInt32(kVK_ANSI_S)
    static let saveURLModifiers: UInt32 = UInt32(cmdKey | optionKey)
}
