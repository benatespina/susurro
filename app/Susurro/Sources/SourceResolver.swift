import AppKit
import ApplicationServices

enum SourceResolver {
    static let supportedBrowserBundles: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.kagi.kagimacOS",
        "com.vivaldi.Vivaldi",
    ]
    static let supportedPDFBundles: Set<String> = [
        "com.apple.Preview",
    ]
    static let supportedTextAppBundles: Set<String> = [
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.iwork.pages",
        "notion.id",
        "md.obsidian",
        "com.literatureandlatte.bear3",
        "com.bear-writer",
        "com.microsoft.Word",
    ]

    static func resolve() -> ResolvedSource? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier
        else { return nil }

        if supportedBrowserBundles.contains(bundleID) {
            if let url = BrowserURLSource.currentURL(pid: app.processIdentifier) {
                return .browserURL(url)
            }
            AppLogger.app.error("source: browser \(bundleID, privacy: .public) matched but no URL via AX")
        }
        if supportedPDFBundles.contains(bundleID) {
            if let url = PDFKitSource.currentDocumentURL(pid: app.processIdentifier) {
                return .pdfFile(url)
            }
            AppLogger.app.error("source: PDF app \(bundleID, privacy: .public) matched but no document URL via AX")
        }
        if supportedTextAppBundles.contains(bundleID) {
            if let result = TextAppSource.extractText(pid: app.processIdentifier) {
                return .fullText(text: result.text, title: result.title)
            }
            AppLogger.app.error("source: text app \(bundleID, privacy: .public) matched but AX walk found no text")
        }
        return nil
    }
}
