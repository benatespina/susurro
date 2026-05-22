import Foundation

actor ArticleExtractor {
    private let session: URLSession
    private let swiftSoupExtract: @Sendable (String, String) -> (text: String, title: String?, containerTag: String?, linkTextLength: Int, totalTextLength: Int)?
    private let readerExtract: @Sendable (String) async throws -> (text: String, title: String?)
    private let strategies: [any ArticleExtractionStrategy]

    init(
        session: URLSession = .shared,
        swiftSoupExtract: @escaping @Sendable (String, String) -> (text: String, title: String?, containerTag: String?, linkTextLength: Int, totalTextLength: Int)? = SwiftSoupExtractor.extract,
        readerExtract: @escaping @Sendable (String) async throws -> (text: String, title: String?) = ReaderModeExtractor.extract,
        strategies: [any ArticleExtractionStrategy] = [XComSyndicationStrategy()]
    ) {
        self.session = session
        self.swiftSoupExtract = swiftSoupExtract
        self.readerExtract = readerExtract
        self.strategies = strategies
    }

    func extract(url: String) async throws -> ExtractedArticle {
        guard
            let parsedURL = URL(string: url),
            let scheme = parsedURL.scheme,
            ["http", "https"].contains(scheme)
        else {
            throw BackendError.extractFailed("invalid url")
        }

        var request = URLRequest(url: parsedURL)
        request.setValue("en-US,en;q=0.9,es;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)

        let html: String
        if let decoded = String(data: data, encoding: .utf8) {
            html = decoded
        } else if let decoded = String(data: data, encoding: .isoLatin1) {
            html = decoded
        } else {
            throw BackendError.extractFailed("invalid encoding")
        }

        var text: String
        var title: String?

        if let soupResult = swiftSoupExtract(html, url),
           ExtractionQualityGate.score(
               text: soupResult.text,
               containerTag: soupResult.containerTag,
               linkTextLength: soupResult.linkTextLength,
               totalTextLength: soupResult.totalTextLength
           ) >= ExtractionQualityGate.acceptThreshold {
            text = soupResult.text
            title = soupResult.title
        } else {
            let tier2Error: (any Error)?
            do {
                let readerResult = try await readerExtract(url)
                text = readerResult.text
                title = readerResult.title
                tier2Error = nil
            } catch {
                text = ""
                title = nil
                tier2Error = error
            }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Tier-2 failed or returned empty — try per-host strategies.
                for strategy in strategies where strategy.canHandle(parsedURL) {
                    do {
                        let result = try await strategy.extract(url: parsedURL)
                        text = result.text
                        title = result.title
                        break
                    } catch {
                        continue
                    }
                }
            }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let tier2Error {
                    throw tier2Error
                }
                throw BackendError.extractFailed("no readable article content")
            }
        }

        let language = LangDetect.detect(text)
        return ExtractedArticle(text: text, title: title, url: url, language: language)
    }
}
