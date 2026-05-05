# Susurro

macOS menu bar app that reads selected text aloud. Select text in any app, click the floating toolbar, hear it spoken.

- Detects text selection via the Accessibility API
- Shows a floating toolbar near the selection
- Streams audio via Edge TTS (default, free) or Azure TTS (optional)
- Includes a `susurro` CLI for Claude Code stop-hook integration

> macOS 26 Tahoe · Apple Silicon (arm64) only · No Intel · No iOS

---

## 📦 Install

1. Download the latest `Susurro.dmg` from [Releases](https://github.com/benatespina/susurro/releases/latest).
2. Open the DMG and drag `Susurro.app` to `/Applications`.
3. Eject the DMG.

**Gatekeeper warning:** because the app is not signed with an Apple Developer certificate, macOS will block the first launch. This is a one-time step — use either method:

- Right-click `Susurro.app` in Applications → **Open** → click **Open** in the dialog.
- Or via Terminal: `xattr -cr /Applications/Susurro.app`, then launch normally.

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

Then relaunch. After the first signed build, subsequent rebuilds keep the same TCC identity — no re-grant needed.

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

## 🤖 Claude Code integration

The bundled `susurro` CLI hooks into Claude Code's `stop` event to read responses aloud as they finish.

- **Enable:** menu bar icon → Claude Code Integration → Install Claude Code hook
- **Disable:** menu bar icon → Claude Code Integration → Uninstall Claude Code hook
- **No audio?** Make sure the Susurro app is running — the hook delegates TTS to the app.

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
