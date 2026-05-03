# Susurro

Local TTS for macOS. Select text in any app → click the floating button → hear it read aloud. No cloud, no subscription. Personal MVP.

## Status

Pre-release. Personal dogfood. Not distributed, not signed for App Store.

## Architecture

- **Backend** (`backend/`): Python FastAPI server serving local TTS via Piper (ONNX-based VITS). Runs as child process of the Swift app.
- **App** (`app/`): Swift macOS menu bar app. Detects text selection via Accessibility API, shows a floating button, plays generated WAV via AVAudioPlayer.

## Requirements

- macOS 26 Tahoe (Apple Silicon — M1+)
- Xcode 26.4 + Swift 6.3
- Homebrew Python 3.12 at `/opt/homebrew/bin/python3.12`

## One-time setup: stable code-signing cert

By default this project uses a self-signed cert called "Susurro Dev" so
that rebuilds preserve the Accessibility (TCC) grant. To install it:

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
cd backend
python3.12 -m venv .venv && .venv/bin/pip install -e '.[dev]'

cd ../app
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
5. Backend loads voices on first launch (downloads ~120 MB once, then instant from cache).

## Usage

- Select text in any supported app → floating button appears near selection
- Click button → text is read aloud (Spanish or English auto-detected)
- New click during playback → cancels current, starts new
- Stop button in menu bar → interrupts playback
- Cmd-Q → clean shutdown (stops backend)

## Supported apps (tested)

- Safari (HTML, PDF)
- Notes
- Preview (PDF)
- Terminal (with Secure Keyboard Entry **off**)

## Known issues

- **Slack and other Electron apps**: `kAXSelectedTextChangedNotification` is unreliable; the panel's mouse-up fallback usually still works but bounds may be off → panel positions near the cursor.
- **First-run voice download**: Piper downloads ~120 MB of voice models on first startup (Spanish + English). Subsequent launches are instant.
- **Terminal**: requires `Terminal → "Secure Keyboard Entry"` off.

## Diagnostics

The menu bar has a Diagnostics submenu:
- Show backend logs (opens Console.app)
- Reveal lockfile in Finder
- Restart backend manually
- Copy diagnostics to clipboard (paste into bug reports)

Backend writes a lockfile at `~/Library/Application Support/Susurro/backend.lock` containing port + bearer token. Piper voice models are cached in `~/Library/Application Support/Susurro/piper-voices/`.

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

- **Local-only TTS**: Python FastAPI + Piper (ONNX VITS) runs entirely on device; no cloud calls, no subscription. Non-autoregressive synthesis delivers <100ms for short utterances on Apple Silicon.
- **Child-process backend**: The Swift app spawns the Python server as a child process and communicates via a lockfile (`backend.lock`) that carries port + bearer token; this avoids a launchd daemon and keeps the two processes tightly coupled to the app lifecycle.
- **Accessibility API for selection detection**: Text selection is captured via `kAXSelectedTextChangedNotification` rather than a global keyboard shortcut, so it works across any app without requiring Input Monitoring permission.
- **Floating-button UX**: A small borderless window appears near the selection bounds and dismisses automatically, keeping the interaction lightweight and non-intrusive.
- **Restart policy**: The backend auto-restarts up to three times on unexpected exit (with a 2-second back-off) before entering a permanent `.crashed` state visible in the menu bar.
