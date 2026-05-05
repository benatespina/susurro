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

## Phase 9 verification

### Automated checks

Run the parity audit suite (gated by `PARITY_AUDIT`; not included in regular builds):

```bash
cd app
xcodebuild -scheme SusurroTests \
  -destination 'platform=macOS' \
  test \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) PARITY_AUDIT' \
  | tee /tmp/p9-parity.log
grep -E "langDetectionAccuracy|extractionSmoke|ParityAudit" /tmp/p9-parity.log | tail -20
```

Expected outcomes:

- `langDetectionAccuracy`: reports ≥95% agreement on the 100-sentence EN/ES corpus (`app/Susurro/Resources/test-fixtures/parity/lang-corpus.json`).
- `extractionSmoke`: for each of the 20 URLs in `app/Susurro/Resources/test-fixtures/parity/extract-urls.txt`, asserts the extracted text is >200 characters, or skips the URL on network error.

Regular test runs (`xcodebuild -scheme SusurroTests test`) do NOT execute these tests — the suite is compiled only when `PARITY_AUDIT` is set.

To record an extraction baseline (for regression comparisons in future runs), capture the JSON printed by the test when no `extract-baseline.json` exists, and save it to `app/Susurro/Resources/test-fixtures/parity/extract-baseline.json`.

### Manual TTS smoke

Perform these steps after a clean build:

1. **Provider Edge, Spanish** — paste a Spanish paragraph into any supported app, select it, click "Read this", confirm intelligible audio is produced.
2. **Provider Edge, English** — repeat with an English paragraph.
3. **Provider Azure, Spanish** — open Settings, enter a valid Azure Cognitive Services key and region, switch the provider to Azure, repeat step 1.
4. **Provider Azure, English** — repeat step 2 with Azure selected.

### Notarization smoke

Run these steps on a development machine with a valid Apple Distribution certificate and notarization credentials:

```bash
# 1. Archive
cd app
xcodebuild -scheme Susurro -configuration Release archive \
  -archivePath /tmp/Susurro.xcarchive

# 2. Export
xcodebuild -exportArchive \
  -archivePath /tmp/Susurro.xcarchive \
  -exportPath /tmp/SusurroExport \
  -exportOptionsPlist ExportOptions.plist

# 3. Notarize
cd /tmp/SusurroExport
zip -r Susurro.app.zip Susurro.app
xcrun notarytool submit Susurro.app.zip \
  --apple-id <your-apple-id> \
  --team-id <your-team-id> \
  --password <app-specific-password> \
  --wait

# 4. Staple
xcrun stapler staple Susurro.app
```

Then validate on a clean macOS account:

1. Drag `Susurro.app` to `/Applications`.
2. Launch it — confirm the menu bar icon appears.
3. Select text in Safari and click "Read this" — confirm audio plays.
4. Confirm no Python interpreter is bundled: `find /Applications/Susurro.app -name "*.py"` should return no output.
5. Confirm no Python process is spawned: `ps -ef | grep python` should show no Susurro-related entry after launch.

## Architecture decisions

- **In-process TTS**: Azure Cognitive Services and Edge TTS run entirely within the Swift app via native WebSocket connections. Non-autoregressive synthesis delivers low-latency audio on Apple Silicon.
- **IPC server**: `IPCServer` exposes the TTS and extraction surface over a local HTTP socket so the `susurro` CLI can drive synthesis without duplicating provider logic.
- **Accessibility API for selection detection**: Text selection is captured via `kAXSelectedTextChangedNotification` rather than a global keyboard shortcut, so it works across any app without requiring Input Monitoring permission.
- **Floating-button UX**: A small borderless window appears near the selection bounds and dismisses automatically, keeping the interaction lightweight and non-intrusive.
