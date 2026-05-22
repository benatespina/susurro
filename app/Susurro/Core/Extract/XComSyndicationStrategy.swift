import Foundation
import JavaScriptCore

struct XComSyndicationStrategy: ArticleExtractionStrategy {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func canHandle(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let allowed: Set<String> = [
            "x.com",
            "www.x.com",
            "mobile.x.com",
            "twitter.com",
            "www.twitter.com",
            "mobile.twitter.com"
        ]
        guard allowed.contains(host) else { return false }
        return tweetID(from: url) != nil
    }

    func extract(url: URL) async throws -> (text: String, title: String?) {
        guard let id = tweetID(from: url) else {
            throw BackendError.extractFailed("x.com: no tweet id in url")
        }

        let ctx = JSContext()!
        let token = ctx.evaluateScript("((\(id)/1e15)*Math.PI).toString(36).replace(/(0+|\\.)/g,'')")?.toString()
        guard let token, !token.isEmpty else {
            throw BackendError.extractFailed("syndication: token computation failed")
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "cdn.syndication.twimg.com"
        components.path = "/tweet-result"
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "token", value: token)
        ]

        guard let syndicationURL = components.url else {
            throw BackendError.extractFailed("syndication URL construction failed")
        }

        var request = URLRequest(url: syndicationURL, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw BackendError.extractFailed("syndication HTTP \(httpResponse.statusCode)")
        }

        let decoded: SyndicationResponse
        do {
            decoded = try JSONDecoder().decode(SyndicationResponse.self, from: data)
        } catch {
            throw BackendError.extractFailed("syndication JSON parse")
        }

        if let article = decoded.article, let preview = article.preview_text, !preview.isEmpty {
            let articleTitle = article.title ?? decoded.user?.name
            if let restId = article.rest_id {
                let articleURLString = "https://x.com/i/article/\(restId)"
                do {
                    let rendered = try await ReaderModeExtractor.extract(url: articleURLString)
                    if rendered.text.count > preview.count {
                        return (rendered.text, rendered.title ?? articleTitle)
                    }
                } catch {
                    // fall through to preview_text
                }
            }
            return (preview, articleTitle)
        }

        let tcoPattern = #"^https?://t\.co/[A-Za-z0-9]+$"#
        if let text = decoded.text, !text.isEmpty {
            let isTcoOnly = text.range(of: tcoPattern, options: .regularExpression) != nil
            if isTcoOnly && decoded.article == nil {
                throw BackendError.extractFailed(
                    "syndication: tweet content not extractable (link-only with no article preview)"
                )
            }
            return (text, decoded.user?.name)
        }

        throw BackendError.extractFailed("syndication: empty payload")
    }

    private func tweetID(from url: URL) -> String? {
        let components = url.pathComponents
        // pathComponents for "/user/status/123" → ["/" , "user", "status", "123"]
        guard components.count >= 4,
              components[2].lowercased() == "status",
              components[3].allSatisfy(\.isNumber),
              !components[3].isEmpty
        else { return nil }
        return components[3]
    }
}

// MARK: - Decodable response model

private struct SyndicationResponse: Decodable {
    struct User: Decodable { let name: String? }
    struct Article: Decodable { let title: String?; let preview_text: String?; let rest_id: String? }
    let text: String?
    let user: User?
    let article: Article?
}
