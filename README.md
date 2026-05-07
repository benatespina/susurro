# Susurro 🗣️

[![Latest Release](https://img.shields.io/github/v/release/benatespina/susurro?style=flat-square)](https://github.com/benatespina/susurro/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![CI](https://github.com/benatespina/susurro/actions/workflows/ci.yml/badge.svg)](https://github.com/benatespina/susurro/actions/workflows/ci.yml)

> **Read aloud anything you select on macOS.** Select text in any app — get instant text-to-speech with native voices.

<!-- Screenshot or demo GIF goes here.
     Suggested: Susurro pill appearing on text selection, then notification on update.
     Save under docs/media/ and reference: ![demo](docs/media/demo.gif) -->

> 📸 _Demo coming soon — meanwhile, see the [latest release](https://github.com/benatespina/susurro/releases/latest)_

Susurro is a macOS menu bar app that reads selected text aloud. It detects your selection via the Accessibility API, shows a floating toolbar, and streams audio through Edge TTS (free, default) or Azure TTS. Built for anyone who wants ears-free reading without leaving their current app.

**Features**
- 🎯 Select text in any app, hear it read aloud
- 🆓 Free voices via Edge TTS (default) or premium voices via Azure TTS
- 🌐 Optional: auto-translate non-Spanish text to Spanish before reading (on-device)
- 🤖 Claude Code integration: hear responses spoken as they finish
- 🔔 Auto-update notifications

> Requires macOS 26 Tahoe · Apple Silicon (arm64)

---

## Install

### Homebrew (recommended)

```bash
brew tap benatespina/susurro https://github.com/benatespina/susurro
brew install --cask susurro
```

Upgrade later with `brew upgrade --cask susurro`.

### DMG

Download [Susurro.dmg](https://github.com/benatespina/susurro/releases/latest/download/Susurro.dmg), open it, drag Susurro.app to `/Applications`.

On first launch, macOS will warn the developer is unidentified (the app isn't signed with an Apple Developer cert):

- **System Settings → Privacy & Security → Open Anyway**, or
- Run `xattr -dr com.apple.quarantine /Applications/Susurro.app` once.

(Optional) Verify checksum: `shasum -a 256 -c Susurro-X.Y.Z.dmg.sha256` (download the `.sha256` file from the release).

---

## Quick start

1. Launch Susurro — its icon appears in the menu bar.
2. macOS will prompt for **Accessibility** permission. Allow it (System Settings → Privacy & Security → Accessibility).
3. Select any text in any app.
4. A floating play button appears — click it.

> **Permissions reset after every update**: each release has a different ad-hoc signature, so macOS treats it as a new app. If Susurro stops responding to text selection after an update:
> ```bash
> tccutil reset Accessibility com.benatespina.susurro
> ```
> Then relaunch and re-grant Accessibility.

---

## Voices

| Provider | Cost | Setup |
|----------|------|-------|
| **Edge TTS** (default) | Free | None — needs internet |
| **Azure TTS** | Pay-as-you-go | See below |

**Azure setup**: create a Speech resource on [Azure Portal](https://portal.azure.com), copy Key + Region (e.g. `westeurope`), open Susurro → menu bar icon → TTS Provider → Configure Azure. Credentials live in the macOS Keychain.

---

## Translate to Spanish

Susurro can translate any non-Spanish selection to Spanish before reading, using Apple's on-device Translation framework.

- **Enable**: menu bar → TTS Provider → toggle **Translate to Spanish before reading**
- **First use**: Susurro will prompt you to install the Spanish language pack (System Settings → General → Language & Region → Translation Languages)

Once installed, translation is instant and offline. If translation fails for any reason, Susurro falls back to reading the original text — never silent.

---

## Claude Code integration

Susurro ships with a `susurro` CLI that hooks into Claude Code's `stop` event — hear Claude's responses as they finish.

- **Install**: menu bar → Claude Code Integration → Install Claude Code hook
- **Uninstall**: menu bar → Claude Code Integration → Uninstall Claude Code hook

The hook delegates to the running Susurro app for TTS.

---

## Updates

Susurro checks for new versions once a day. When available, you'll get a system notification — click it to open the release page.

Trigger a manual check via the menu bar icon → **Check for Updates…**.

If you installed via Homebrew: `brew upgrade --cask susurro`.

---

## Development

**Requirements**: macOS 26 Tahoe, Xcode 26 (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/benatespina/susurro.git
cd susurro
bash scripts/create_signing_cert.sh   # one-time: local cert keeps Accessibility grant across rebuilds
cd app && xcodegen generate
open Susurro.xcodeproj
```

**Tests**: `cd app && xcodebuild -scheme SusurroTests -destination 'platform=macOS' test`

**Project layout**:
- `app/Susurro/` — main app (SwiftUI + AppKit menu bar)
- `app/CLI/` — `susurro` CLI for Claude Code integration
- `app/SusurroTests/` — Apple Testing framework
- `app/project.yml` — XcodeGen manifest
- `scripts/` — build helpers
- `Casks/susurro.rb` — Homebrew Cask formula

---

## License

MIT — see [LICENSE](LICENSE). © 2026 Beñat Espiña.

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, conventions, and what's in/out of scope.
