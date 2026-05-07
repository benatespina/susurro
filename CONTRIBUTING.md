# Contributing

Thanks for your interest. Here's how to set up locally and submit a change.

## Development setup

Requirements: macOS 26 Tahoe, Xcode 26 (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/benatespina/susurro.git
cd susurro
bash scripts/create_signing_cert.sh   # one-time, keeps Accessibility grant across rebuilds
cd app
xcodegen generate
open Susurro.xcodeproj
```

## Tests

```bash
cd app && xcodebuild -scheme SusurroTests -destination 'platform=macOS' test
```

CI runs the same suite on every PR.

## Commits & branches

- Conventional Commits: `feat(scope):`, `fix(scope):`, `chore(scope):`, `docs:`, etc.
- Branch from `main`. PRs target `main`.
- Squash merge enabled — keep your commits clean, but don't rebase-bombing on every comment.

## What kind of contributions are welcome?

- Bug reports with clear repro steps
- Feature ideas (open a discussion first if substantial)
- Pull requests with tests for any logic change
- Documentation improvements
- New TTS providers (follow the existing `Core/TTS/<Provider>` pattern)

## What's out of scope (for now)

- Cross-platform (Linux/Windows): Susurro is macOS-native by design
- Intel Mac support: Apple Silicon only
- Apple Developer ID code signing: tracked separately

## Issues

If you're not sure something is a bug or a feature, [start a discussion](https://github.com/benatespina/susurro/discussions).
