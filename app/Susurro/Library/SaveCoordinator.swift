import AppKit
import Foundation

// MARK: - Protocols for dependency injection

/// Abstracts source resolution so `SaveCoordinator` can be tested without
/// hitting the live AX/accessibility APIs.
protocol SourceResolving: Sendable {
    func resolve() -> ResolvedSource?
    func urlFromClipboard() -> String?
}

/// Abstracts the synthesizer's enqueue call so tests can inject a recording fake.
protocol Enqueuing: Sendable {
    func enqueue(itemID: UUID) async
}

// MARK: - Live implementations

/// Production `SourceResolving` that delegates to the existing static helpers.
struct LiveSourceResolver: SourceResolving {
    func resolve() -> ResolvedSource? {
        SourceResolver.resolve()
    }

    func urlFromClipboard() -> String? {
        SourceResolver.urlFromClipboard()
    }
}

extension LibrarySynthesizer: Enqueuing {}

// MARK: - SourceResolver clipboard helper

extension SourceResolver {
    /// Extracts a valid http/https URL from the system clipboard, or returns `nil`.
    static func urlFromClipboard() -> String? {
        let pb = NSPasteboard.general
        let raw = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let parsed = URL(string: raw),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false
        else { return nil }
        return parsed.absoluteString
    }
}

// MARK: - SaveCoordinator

/// Routes a "save to reading list" action from any entry point (hotkey, toolbar button)
/// to the `LibraryStore` + `LibrarySynthesizer`, with source inference via `SourceResolver`.
@MainActor
final class SaveCoordinator {

    private let store: LibraryStore
    private let synthesizer: any Enqueuing
    private let resolver: any SourceResolving

    init(
        store: LibraryStore,
        synthesizer: any Enqueuing,
        resolver: any SourceResolving = LiveSourceResolver()
    ) {
        self.store = store
        self.synthesizer = synthesizer
        self.resolver = resolver
    }

    // MARK: - Public API

    /// Single entry point. Infers the source, saves an item, and enqueues synthesis.
    func saveFromFrontmost() async {
        let resolved = resolver.resolve()

        if let source = resolved {
            await save(from: source)
            return
        }

        // Fallback: clipboard URL.
        if let url = resolver.urlFromClipboard() {
            AppLogger.app.info("SaveCoordinator: no frontmost source, using clipboard URL")
            await addAndEnqueue(item: makeURLItem(url: url))
            return
        }

        AppLogger.app.info("SaveCoordinator: no source found in frontmost app or clipboard")
        NSSound.beep()
    }

    // MARK: - Private

    private func save(from source: ResolvedSource) async {
        switch source {
        case .browserURL(let url):
            AppLogger.app.info("SaveCoordinator: saving browser URL \(url.prefix(80), privacy: .public)")
            await addAndEnqueue(item: makeURLItem(url: url))

        case .fullText(let text, let title):
            let resolvedTitle: String
            if let t = title, !t.isEmpty {
                resolvedTitle = t
            } else {
                let prefix = String(text.prefix(50))
                resolvedTitle = text.count > 50 ? prefix + "…" : prefix
            }
            AppLogger.app.info("SaveCoordinator: saving text item title=\(resolvedTitle.prefix(60), privacy: .public)")
            await addAndEnqueue(item: makeTextItem(text: text, title: resolvedTitle))

        case .pdfFile(let url):
            AppLogger.app.info("SaveCoordinator: extracting PDF at \(url.lastPathComponent, privacy: .public)")
            do {
                let content = try PDFKitSource.extractText(from: url)
                let title = content.title ?? url.deletingPathExtension().lastPathComponent
                await addAndEnqueue(item: makeTextItem(text: content.text, title: title))
            } catch {
                AppLogger.app.error("SaveCoordinator: PDF extraction failed: \(error, privacy: .public)")
                NSSound.beep()
            }
        }
    }

    private func addAndEnqueue(item: LibraryItem) async {
        store.add(item)
        AppLogger.app.info("SaveCoordinator: added item \(item.id.uuidString, privacy: .public) kind=\(item.sourceKind.rawValue, privacy: .public)")
        await synthesizer.enqueue(itemID: item.id)
    }

    // MARK: - Item factories

    private func makeURLItem(url: String) -> LibraryItem {
        LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: nil,
            sourceURL: url,
            sourceKind: .url,
            rawText: nil,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
    }

    private func makeTextItem(text: String, title: String) -> LibraryItem {
        LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: title,
            sourceURL: nil,
            sourceKind: .text,
            rawText: text,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
    }
}
