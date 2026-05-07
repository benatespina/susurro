# Susurro

[![Latest Release](https://img.shields.io/github/v/release/benatespina/susurro?style=flat-square)](https://github.com/benatespina/susurro/releases/latest)

macOS menu bar app that reads selected text aloud. Select text in any app, click the floating toolbar, hear it spoken.

- Detects text selection via the Accessibility API
- Shows a floating toolbar near the selection
- Streams audio via Edge TTS (default, free) or Azure TTS (optional)
- Optional: translates non-Spanish text to Spanish before reading (Apple Translation framework, on-device)
- Includes a `susurro` CLI for Claude Code stop-hook integration

> macOS 26 Tahoe · Apple Silicon (arm64) only · No Intel · No iOS

---

## 📦 Install (Homebrew)

Recommended for easy upgrades.

```bash
brew tap benatespina/susurro https://github.com/benatespina/susurro
brew install --cask susurro
```

To upgrade later: `brew upgrade --cask susurro`.

## 📦 Install (DMG)

Download the latest DMG: [Susurro.dmg](https://github.com/benatespina/susurro/releases/latest/download/Susurro.dmg)

Open the DMG, drag `Susurro.app` to `/Applications`, then on first launch:

- macOS will say the developer is unidentified. Open **System Settings → Privacy & Security** and click **Open Anyway**.
- Or run: `xattr -dr com.apple.quarantine /Applications/Susurro.app`

Verify checksum (optional):

```bash
shasum -a 256 -c Susurro-X.Y.Z.dmg.sha256
```

Replace `X.Y.Z` with the version. The `.sha256` file is attached to each release.

**Upgrading from a prior release:** macOS caches Accessibility permission per binary signature. After replacing `Susurro.app` with a new version, reset the cached grant so the new binary is recognised, then relaunch and re-grant Accessibility when prompted:

```bash
tccutil reset Accessibility com.benatespina.susurro
```

### Build from source

**Requirements:** macOS 26 Tahoe, Apple Silicon, Xcode 26 with Swift 6, `xcodegen` (`brew install xcodegen`)

```bash
git clone https://github.com/benatespina/susurro.git
cd susurro

# One-time: create a local signing cert so Accessibility permission survives rebuilds
bash scripts/create_signing_cert.sh

# Generate and build
cd app && xcodegen generate
xcodebuild -project Susurro.xcodeproj -scheme Susurro -configuration Debug -derivedDataPath build build

# Launch
open ./build/Build/Products/Debug/Susurro.app
```

To keep it permanent, drag `Susurro.app` from `build/Build/Products/Debug/` to `/Applications`.

---

## 🚀 Getting Started

**First run:** macOS will prompt for Accessibility permission so Susurro can read selected text in other apps.

1. Click "Open System Settings" in the prompt.
2. Go to Privacy & Security → Accessibility.
3. Toggle Susurro on.
4. Quit and relaunch Susurro.

**Usage:**

- Select text in any app.
- A floating toolbar appears near the selection.
- Click play to hear it read aloud.
- Click stop to halt playback.

**Stuck on permissions?** Reset and re-grant with:

```bash
tccutil reset Accessibility com.benatespina.susurro
```

Then relaunch. Each new DMG release has a different ad-hoc signature, so this reset is needed after every update. Local dev builds signed with the self-signed cert from `scripts/create_signing_cert.sh` keep the same TCC identity across rebuilds.

---

## 🔊 Voices

| Provider | Default | Cost | Setup |
|----------|---------|------|-------|
| Edge TTS | Yes | Free | None — requires internet |
| Azure TTS | No | Azure pricing | See below |

**Azure TTS setup:**

1. Create an Azure Speech resource at https://portal.azure.com.
2. Copy the **Key** and **Region** (e.g. `westeurope`).
3. In Susurro: menu bar icon → Settings → paste key + region → switch provider to Azure.

Credentials are stored in the system Keychain.

---

## 🌐 Translate to Spanish

Susurro can translate non-Spanish selected text to Spanish before reading it aloud, using Apple's on-device Translation framework. Spanish text is read directly (no translation).

**Enable:**

1. Menu bar icon → **TTS Provider** → toggle **Translate to Spanish before reading** on (`✓`).

**First use — install the language model:**

The Translation framework requires a per-language model. Susurro detects when the model is missing and shows a one-time alert directing you to System Settings.

1. Select non-Spanish text and click play. Susurro shows an alert: *Spanish translation model not installed*.
2. Click **Open System Settings**. Settings opens to **General → Language & Region**.
3. Click **Translation Languages** → **Add Language** → choose **Spanish (any variant)** → confirm.
4. Wait for the download to finish (button switches to **Remove**).
5. Back in Susurro, retry — the text is translated and read in `es-ES-AlvaroNeural` (Edge TTS) or the equivalent Azure voice.

**Notes:**

- Once the model is installed, subsequent translations are instant and offline.
- If translation fails for any reason, Susurro falls back to reading the original text — never silent.
- The toggle persists across launches.

---

## 🤖 Claude Code integration

The bundled `susurro` CLI hooks into Claude Code's `stop` event to read responses aloud as they finish.

- **Enable:** menu bar icon → Claude Code Integration → Install Claude Code hook
- **Disable:** menu bar icon → Claude Code Integration → Uninstall Claude Code hook
- **No audio?** Make sure the Susurro app is running — the hook delegates TTS to the app.

---

## 🔔 Updates

Susurro checks for new versions once per day in the background. When a new version is available, you'll get a system notification — click it to open the release page on GitHub.

You can also trigger a check manually via the menu bar icon → **Check for Updates…**.

---

## 🛠️ Development

**Prerequisites:** macOS 26 Tahoe, Apple Silicon, Xcode 26 with Swift 6, `xcodegen` (`brew install xcodegen`)

```bash
cd app
xcodegen generate        # regenerate after editing project.yml
open Susurro.xcodeproj   # open in Xcode
```

**Tests:**

```bash
cd app && xcodebuild -scheme SusurroTests -destination 'platform=macOS' test
```

**Project layout:**

- `app/Susurro/` — main app source
- `app/SusurroTests/` — tests
- `app/project.yml` — XcodeGen manifest
- `scripts/` — signing cert and helpers
