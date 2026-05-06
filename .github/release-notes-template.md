## Susurro v{{VERSION}}

Read-aloud helper for macOS.

### Install

**Homebrew (recommended):**

```
brew tap benatespina/susurro https://github.com/benatespina/susurro
brew install --cask susurro
```

**DMG:**

Download [Susurro.dmg](https://github.com/benatespina/susurro/releases/latest/download/Susurro.dmg) (always-latest) or `Susurro-{{VERSION}}.dmg` (versioned).

Open the DMG, drag `Susurro.app` to `/Applications`, then on first launch:

macOS will warn that the developer is unidentified. To allow it:

```
xattr -dr com.apple.quarantine /Applications/Susurro.app
```

Or open **System Settings → Privacy & Security** and click **Open Anyway**.

### Verify checksum

```
shasum -a 256 -c Susurro-{{VERSION}}.dmg.sha256
```

### Changelog

See [commit log](https://github.com/benatespina/susurro/commits/v{{VERSION}}).
