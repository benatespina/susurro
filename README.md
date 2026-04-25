Susurro — local TTS for macOS via text selection. MVP in progress.

## Resetting Accessibility for testing

Susurro is registered with TCC under bundle ID `com.benatespina.susurro`. To force the
permission flow again for testing:

    tccutil reset Accessibility com.benatespina.susurro

Then relaunch Susurro.

## Known Issues (Phase 6)

### Per-app AX API findings

The AX spike could not be executed from the command line (`xcrun swift` runs as an untrusted process). Findings below are based on documented macOS AX behaviour and in-app testing.

**Safari (HTML)** — `kAXSelectedTextAttribute` works. `AXSelectedTextBounds` available via `kAXBoundsForRangeParameterizedAttribute` fallback when the direct attribute is missing. Panel positioning works.

**Safari (PDF)** — PDF plugin uses a different AX tree; `kAXSelectedTextAttribute` may return an empty string for PDF text selections in some Safari versions. Panel falls back to mouse-cursor positioning when bounds are nil.

**Slack** — Electron-based. `AXSelectedTextBounds` is typically absent; the `kAXBoundsForRangeParameterizedAttribute` fallback also often fails. Panel appears near the mouse cursor. Known limitation.

**Notes** — Full AX support. `kAXSelectedTextAttribute` and bounds both available. Panel positions correctly above/below selection.

**Preview (PDF)** — PDFKit exposes `kAXSelectedTextAttribute` on the PDF view element. Bounds available via `kAXBoundsForRangeParameterizedAttribute`. Panel positioning works.

**Terminal** — `kAXSelectedTextAttribute` returns the selected text when Secure Keyboard Entry is **disabled**. With Secure Keyboard Entry enabled (Terminal → Secure Keyboard Entry), AX reads are blocked entirely and the panel will not appear. To test: disable via Terminal menu → uncheck "Secure Keyboard Entry".

### General limitations

- `kAXSelectedTextChangedNotification` fires on the app-level AX element for most apps. Some apps (notably Electron apps like Slack) do not fire this notification reliably. The observer also subscribes to the focused window element as a fallback.
- Rapid selection changes are rate-limited to at most one panel update per 50 ms to avoid excessive AX reads.
- Panel bounds positioning uses the global AX coordinate system (top-left origin). The `PanelPositioner` converts to Cocoa bottom-left coordinates. Some apps return bounds in an unexpected coordinate space; the panel may appear slightly misaligned in those cases.
