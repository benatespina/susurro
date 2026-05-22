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

## X (Twitter) Article extraction limit

`x.com/<user>/status/<id>` tuits whose body is just a `t.co` link to an
X Article (`x.com/i/article/<id>`) extract only the syndication
`preview_text` (~200 chars + title) via `XComSyndicationStrategy`. The
full article body is NOT accessible without a logged-in session: X
serves a login wall to a clean WKWebView even with a real Safari
User-Agent, a long hydration window, and a cookie-banner dismissal pass.

Confirmed Safari incognito sees the article — but only because it
inherits residual session cookies. Clean WKWebView never has those.

Cookie pre-seeding from the user's Safari is out of scope (requires
`Automation` TCC permission + brittle X cookie identification).

If a future fix is desired: render via `SFSafariViewController` or
require a one-time login flow at app onboarding.
