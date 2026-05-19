# Susurro — Agent Notes

## Accessibility permission stuck on "denied"

After rebuild or signing change (cert rotation, Manual↔Automatic, team-id),
`AXIsProcessTrustedWithOptions` returns `denied` even after the user toggles
Susurro ON in System Settings. TCC binds grants to `cdhash` + signing
requirement; new build = stale grant. PR #31 (Automatic signing) makes it
worse.

```bash
tccutil reset Accessibility com.benatespina.susurro
# kill running Susurro, relaunch the .app
```

Multiple `Successfully reset …` lines = stale duplicates, confirms diagnosis.
Not a code bug — do not touch `AccessibilityPermission`.

## Test suite parallel-Keychain flake

`DriveConfigTests` + `LibraryPublisherTests` both touch system Keychain.
Pass solo, flake in parallel. Pre-existing — do not chase. Keep
`withIsolatedDriveStorage` / `withIsolatedStorage` helpers.
