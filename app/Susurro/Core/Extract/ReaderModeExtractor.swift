import Foundation
import WebKit

@MainActor
enum ReaderModeExtractor {
    static func extract(url: String) async throws -> (text: String, title: String?) {
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

        let js = """
        (function() {
            try {
                var doc = new Readability(document.cloneNode(true)).parse();
                return doc ? JSON.stringify({title: doc.title || null, textContent: doc.textContent || ''}) : null;
            } catch(e) {
                return null;
            }
        })()
        """

        let result = try await webView.evaluateJavaScript(js)

        guard let jsonString = result as? String else {
            throw BackendError.extractFailed("reader returned no content")
        }

        guard
            let data = jsonString.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
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
