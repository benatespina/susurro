import Foundation
import WebKit

@MainActor
enum ReaderModeExtractor {
    static func extract(url: String) async throws -> (text: String, title: String?) {
        NSLog("[ReaderMode] start url=\(url)")
        guard let resolvedURL = URL(string: url) else {
            throw BackendError.extractFailed("invalid url")
        }

        let readabilityJS = try loadReadabilityJS()

        let webView = WKWebView(frame: .zero)
        webView.configuration.suppressesIncrementalRendering = true

        let userScript = WKUserScript(
            source: readabilityJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(userScript)

        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        webView.load(URLRequest(url: resolvedURL))

        let navigationResult = try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await delegate.waitForNavigation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw BackendError.extractFailed("reader mode timed out")
            }
            try await group.next()
            group.cancelAll()
        }
        _ = navigationResult

        // SPAs (x.com, Next.js docs) fire didFinish before React hydrates; Readability returns null.
        // Poll with capped backoff so the first attempt on static pages pays zero extra latency.
        // callAsyncJavaScript is required here: evaluateJavaScript returns a Promise object rather
        // than awaiting it, so the backoff delays would never execute and the cast to String fails.
        // Pre-pass dismisses cookie banners on each iteration so Readability sees the article DOM.
        // Budget: [0, 500, 1500, 3000, 4500, 4500] ≈ 14s total, safely under the outer 15s timeout.
        let js = """
        const delays = [0, 500, 1500, 3000, 4500, 4500];
        let lastResult = null;
        for (let i = 0; i < delays.length; i++) {
            const delay = delays[i];
            await new Promise(r => setTimeout(r, delay));
            // Dismiss cookie/consent overlays so Readability can see the article.
            // Heuristic: find buttons whose visible text matches a common accept/agree phrase
            // and click them; also remove fullscreen dialogs/overlays as a fallback.
            try {
              const acceptPattern = /\\b(accept|agree|allow|got it|aceptar|akzeptieren|accepter|accetta|consent)\\b/i;
              const buttons = Array.from(document.querySelectorAll('button, [role="button"], a, input[type="button"], input[type="submit"]'));
              for (const btn of buttons) {
                const text = (btn.innerText || btn.value || btn.getAttribute('aria-label') || '').trim();
                if (text && text.length < 60 && acceptPattern.test(text)) {
                  try { btn.click(); } catch (e) {}
                }
              }
              // Also remove obvious modal overlays so Readability isn't fooled by their text.
              const overlaySelectors = [
                '[role="dialog"][aria-modal="true"]',
                '[data-testid*="cookie"]',
                '[id*="cookie-banner"]',
                '[class*="cookie-banner"]',
                '[id*="consent"]',
                '[class*="consent"]',
              ];
              for (const sel of overlaySelectors) {
                document.querySelectorAll(sel).forEach((el) => {
                  try { el.remove(); } catch (e) {}
                });
              }
            } catch (e) {
              // never let dismissal failures break extraction
            }
            let result = null;
            try {
                result = new Readability(document.cloneNode(true)).parse();
            } catch (e) {
                result = null;
            }
            console.log(`[ReaderMode JS] delay=${delay} attempt=${i} text_len=${result?.textContent?.length || 0}`);
            if (result && typeof result.textContent === 'string' && result.textContent.length >= 200) {
                return JSON.stringify({title: result.title || null, textContent: result.textContent});
            }
            if (result !== null) {
                lastResult = result;
            }
        }
        if (lastResult !== null) {
            return JSON.stringify({title: lastResult.title || null, textContent: lastResult.textContent});
        }
        return null;
        """

        let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page)

        let parsedForLog: [String: Any]? = {
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj
        }()
        let extractedTextLength = (parsedForLog?["textContent"] as? String)?.count ?? 0
        NSLog("[ReaderMode] url=\(resolvedURL.absoluteString) result_text_len=\(extractedTextLength) title=\(parsedForLog?["title"] as? String ?? "nil")")

        guard let jsonString = result as? String else {
            NSLog("[ReaderMode] throwing extractFailed for url=\(resolvedURL.absoluteString)")
            throw BackendError.extractFailed("reader returned no content")
        }

        guard
            let data = jsonString.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            NSLog("[ReaderMode] throwing extractFailed for url=\(resolvedURL.absoluteString)")
            throw BackendError.extractFailed("reader returned no content")
        }

        let text = (parsed["textContent"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parsed["title"] as? String

        return (text, title)
    }

    private static func loadReadabilityJS() throws -> String {
        guard
            let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw BackendError.extractFailed("Readability.js not found in bundle")
        }
        return source
    }
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForNavigation() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
