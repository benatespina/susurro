# Susurro

Local TTS for macOS. Select text in any app → click the floating button → hear it read aloud. No cloud subscription required for Edge TTS; Azure TTS requires an Azure Cognitive Services key configured in-app.

## Status

Pre-release. Personal dogfood. Not distributed.

## Architecture

All logic runs in-process inside the Swift macOS app — there is no separate backend process.

- **App** (`app/`): Swift macOS menu bar app. Detects text selection via Accessibility API, shows a floating button, plays generated audio via AVAudioPlayer.
- **IPC** (`app/Susurro/IPC/`): In-process backend facade (`BackendClient`) and IPC server (`IPCServer`) that exposes the same HTTP surface to the `susurro` CLI tool.
- **TTS providers**: Azure Cognitive Services (streaming PCM via WebSocket) and Edge TTS (Microsoft's public WebSocket endpoint). Provider is selected in the Settings window.
- **HTML extraction**: SwiftSoup + WKWebView Reader Mode strip markup before synthesis.

## Requirements

- macOS 26 Tahoe (Apple Silicon — M1+)
- Xcode 26.4 + Swift 6.3

## Azure setup

Azure TTS requires a Cognitive Services resource in your Azure subscription.

1. Create an Azure Cognitive Services (Speech) resource.
2. Copy the **Key** and **Region** (e.g. `westeurope`).
3. Open Susurro → menu bar icon → **Settings** → enter the key and region there.

No environment variables or config files are needed; credentials are stored in the system Keychain.

## One-time setup: stable code-signing cert

By default this project uses a self-signed cert called "Susurro Dev" so that rebuilds preserve the Accessibility (TCC) grant. To install it:

```bash
bash scripts/create_signing_cert.sh
```

You'll be prompted for your macOS password once (to trust the cert for code signing). Then rebuild:

```bash
cd app && xcodegen generate && xcodebuild -project Susurro.xcodeproj -scheme Susurro -configuration Debug -derivedDataPath build build
```

Re-grant Accessibility one final time after the first signed build. Subsequent rebuilds will keep the same TCC identity, so no re-grant needed.

## Build

```bash
cd app
xcodegen generate
xcodebuild -project Susurro.xcodeproj -scheme Susurro -configuration Debug -derivedDataPath build build
```

## Run

**Important**: launch via Launch Services so macOS routes Accessibility/TCC correctly:

```bash
open ./app/build/Build/Products/Debug/Susurro.app
```

Direct invocation of `Susurro.app/Contents/MacOS/Susurro` from a terminal can interfere with the native AX prompt.

## First-run

1. App launches, shows speaker icon in menu bar.
2. Permission window appears — click "Open System Settings".
3. Toggle Susurro on in Privacy & Security → Accessibility.
4. Bring Susurro frontmost (click menu icon) → permission window auto-closes.

## Usage

- Select text in any supported app → floating button appears near selection
- Click button → text is read aloud (Spanish or English auto-detected)
- New click during playback → cancels current, starts new
- Stop button in menu bar → interrupts playback
- Cmd-Q → clean shutdown

## Supported apps (tested)

- Safari (HTML, PDF)
- Notes
- Preview (PDF)
- Terminal (with Secure Keyboard Entry **off**)

## Known issues

- **Slack and other Electron apps**: `kAXSelectedTextChangedNotification` is unreliable; the panel's mouse-up fallback usually still works but bounds may be off → panel positions near the cursor.
- **Terminal**: requires `Terminal → "Secure Keyboard Entry"` off.

## Diagnostics

The menu bar has a Diagnostics submenu:
- Show logs (opens Console.app)
- Copy diagnostics to clipboard (paste into bug reports)

## Resetting Accessibility for testing

Only needed after the initial cert setup + first signed build, or when explicitly testing the AX prompt:

```
tccutil reset Accessibility com.benatespina.susurro
```

Then relaunch. Subsequent rebuilds with the same "Susurro Dev" cert do not require re-granting.

## Claude Code integration

Susurro can automatically read Claude's responses aloud as they finish. It hooks into Claude Code's `stop` event, extracts the last assistant message, filters out code blocks, and speaks the prose.

### Install

1. Open Susurro → click the menu bar icon.
2. **Claude Code Integration → Install command-line tool** — installs the `susurro` CLI to `/usr/local/bin`.
3. **Claude Code Integration → Install Claude Code integration** — writes the stop hook into `~/.claude/settings.json`.
4. **Claude Code Integration → Auto-read responses** — toggle on.

Send any message in a Claude Code session; Susurro will speak the response.

### Disable per-project

Place a `.susurro-disable` marker in any project directory:

```bash
touch .susurro-disable
```

The hook walks up from the current working directory to `$HOME` and skips silently if it finds the marker. Remove the file to re-enable. You can also toggle it from the menu while in a Claude session for that project (**Claude Code Integration → Disable in "project-name"**).

### Troubleshooting

Verify the CLI is on `$PATH`:

```bash
which susurro
```

Check hook logs (last hour):

```bash
log show --predicate 'subsystem CONTAINS "Susurro"' --last 1h
```

Enable verbose hook logging — writes to `~/Library/Logs/Susurro/hook.log`:

```bash
export SUSURRO_DEBUG=1
```

Set this in your shell profile so it persists across Claude Code sessions.

## Architecture decisions

- **In-process TTS**: Azure Cognitive Services and Edge TTS run entirely within the Swift app via native WebSocket connections. Non-autoregressive synthesis delivers low-latency audio on Apple Silicon.
- **IPC server**: `IPCServer` exposes the TTS and extraction surface over a local HTTP socket so the `susurro` CLI can drive synthesis without duplicating provider logic.
- **Accessibility API for selection detection**: Text selection is captured via `kAXSelectedTextChangedNotification` rather than a global keyboard shortcut, so it works across any app without requiring Input Monitoring permission.
- **Floating-button UX**: A small borderless window appears near the selection bounds and dismisses automatically, keeping the interaction lightweight and non-intrusive.
