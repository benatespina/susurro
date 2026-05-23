# Cookies — Chromium cookie pre-seeding for X Article extraction

This module gives `XComSyndicationStrategy` access to the user's
X session cookies so a clean WKWebView can load the full body of
an X Article (`x.com/i/article/<id>`) instead of hitting the
login wall.

## Components

```
BrowserDetector ─────────┐
                         ▼
DefaultBrowserCookieProvider
     │
     ├── ChromiumCookieAdapter(.chrome) ──┐
     ├── ChromiumCookieAdapter(.arc)   ──┤
     ├── ChromiumCookieAdapter(.brave) ──┤
     └── ChromiumCookieAdapter(.edge)  ──┤
                                         ▼
                    SQLiteCookieReader   KeychainAccessor
                                         (Safe Storage entry)
                                              │
                                              ▼
                                      ChromiumCrypto
                               (PBKDF2 + AES-CBC-128)
```

## Flow per `cookies(forDomain:)`

1. `BrowserDetector` returns the system default browser (or nil)
   and the list of installed Chromium browsers.
2. Candidates = `[default] + [chrome, arc, brave, edge]`, deduped,
   filtered to installed.
3. For each candidate, the adapter:
   - Reads the AES key from the browser's `<Name> Safe Storage`
     Keychain entry (cached in memory after first read).
   - Copies the Cookies SQLite file to a temp path (avoids lock
     contention with a running browser).
   - Queries rows matching `host_key LIKE '%.x.com'` /
     `'%.twitter.com'`.
   - Decrypts each `encrypted_value` (PBKDF2-HMAC-SHA1 salt
     "saltysalt" iter 1003 keylen 16; AES-CBC-128 IV `0x20`x16
     PKCS7; v10/v11 prefix; optional 32-byte SHA-256 plaintext
     prefix from Chrome >=130 is stripped).
   - Skips per-row decrypt failures.
4. First candidate whose cookies contain both `auth_token` and
   `ct0` wins. Returns `[HTTPCookie]`.

## Test fixtures

- `ChromiumCryptoTests` uses inline hex vectors + a round-trip
  helper. Run hermetically — no I/O.
- `SQLiteCookieReaderTests` builds a Chromium-style SQLite
  fixture in `temporaryDirectory`; cleaned up via `defer`.
- `ChromiumCookieAdapterTests` uses the `databaseURL` override
  to inject a temp DB — never touches real `~/Library` paths.
- `DefaultBrowserCookieProviderTests` injects fake `defaultBrowser`,
  `isSafariOnly`, `installedBrowsers` closures and a stub
  `adapterFactory`.

## Troubleshooting

- **"Allow Keychain access" prompt fires every time**: the user
  chose "Allow Once" rather than "Always Allow". To clear the
  ACL and re-prompt: open Keychain Access.app → search for
  `<Browser> Safe Storage` → right-click → Get Info → Access
  Control → remove Susurro from the list. Next extraction will
  re-prompt; choose "Always Allow".
- **Wrong browser used**: the system default browser is picked
  first. Change macOS System Settings → Desktop & Dock →
  Default web browser.
