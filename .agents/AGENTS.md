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
