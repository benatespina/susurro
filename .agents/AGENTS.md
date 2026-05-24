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

## Per-config entitlements: Debug full, Release minimal

Susurro distributes via Homebrew cask without a paid Apple Developer
Program. DMGs are ad-hoc signed by CI. Ad-hoc signatures cannot
validate **restricted entitlements** (`keychain-access-groups`,
`com.apple.developer.*`, `application-groups`, etc.) — AMFI rejects at
the kernel level before Gatekeeper can show "Open Anyway". This was
the v0.5.0 cask install bug.

Two entitlements files, wired per-configuration in `app/project.yml`:

- `app/Susurro/Susurro.entitlements` (Debug) — full set including
  `keychain-access-groups`. Developer machine signs with local Apple
  Development cert that validates the group.
- `app/Susurro/Susurro-Release.entitlements` (Release) — minimal,
  no restricted entitlements. Currently only `app-sandbox=false`.
  Ad-hoc signing passes AMFI.

```yaml
# app/project.yml — Susurro target
settings:
  configs:
    Debug:
      CODE_SIGN_ENTITLEMENTS: Susurro/Susurro.entitlements
    Release:
      CODE_SIGN_ENTITLEMENTS: Susurro/Susurro-Release.entitlements
```

**Regression rule**: any new entitlement added to
`Susurro.entitlements` must be evaluated for whether it's "restricted"
(needs cert to validate). If yes, do NOT add to
`Susurro-Release.entitlements` — accept the runtime cost (e.g. an
extra macOS prompt when end users first use the feature) instead.
Adding a restricted entitlement to Release without paid Developer ID
will break cask install on every machine that isn't yours.

`release.yml` signs Release ad-hoc (`CODE_SIGN_IDENTITY="-"`). Do not
re-introduce cert install / provisioning profile steps unless the
project gets a paid Developer ID + notarization workflow (see PRs
#38, #39, #40 history for context).

## Test suite parallel-Keychain flake

`DriveConfigTests` + `LibraryPublisherTests` both touch system Keychain.
Pass solo, flake in parallel. Pre-existing — do not chase. Keep
`withIsolatedDriveStorage` / `withIsolatedStorage` helpers.

## X (Twitter) Article extraction

`x.com/<user>/status/<id>` tuits whose body is a `t.co` link to an
X Article (`x.com/i/article/<id>`) are extracted in full by
`XComSyndicationStrategy` via cookie pre-seeding from a Chromium
browser.

Flow: `DefaultBrowserCookieProvider` reads session cookies
(`auth_token`, `ct0`, ...) from one of Chrome / Arc / Brave /
Microsoft Edge (whichever is the system default browser; falls
back to chrome → arc → brave → edge if the default has no x.com
session). Cookies are decrypted on the fly (PBKDF2-HMAC-SHA1 +
AES-CBC-128, keys cached in memory per session) and injected into
a non-persistent WKWebView before loading the article URL.

First time per browser the user gets a macOS Keychain ACL prompt
"Susurro wants to use confidential information stored in <browser>
Safe Storage". Choose Allow or Always Allow.

Implementation lives in `app/Susurro/Core/Extract/Cookies/`.

Actionable errors surfaced once per session via
`BrowserCookieHelpWindow`:
- `.onlySafariDetected` — Safari is default and no Chromium
  browser installed.
- `.noBrowserDetected` — no supported browser installed.
- `.keychainDenied` — user declined the Keychain ACL prompt.
- `.noXSessionCookies` — no Chromium browser has an x.com
  session.

Silent (logged only): `.databaseUnavailable`, `.keychainNotFound`,
`.decryptionFailed`.

**Safari NOT supported in v1.** AppleScript no longer exposes
Safari cookies, and reading the binarycookies file in
`~/Library/Containers/com.apple.Safari/` requires Full Disk
Access TCC, which forces an app relaunch after grant — breaks the
lazy first-use UX. Documented as future work.
