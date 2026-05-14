import SwiftUI

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @State private var newURL: String = ""
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Paste URL", text: $newURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addURL() }
            Button("Add") { addURL() }
                .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isValidURL(newURL))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            itemList
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No items yet. Paste a URL above or drag one in.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var itemList: some View {
        List(store.items, id: \.id, selection: $selection) { item in
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle(for: item))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(relativeDate(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill(for: item.status)
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    store.remove(id: item.id)
                }
            }
        }
        .onDeleteCommand {
            if let id = selection {
                store.remove(id: id)
                selection = nil
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                addItem(url: url.absoluteString, kind: .url)
            }
            return !urls.isEmpty
        }
        .dropDestination(for: String.self) { strings, _ in
            for string in strings {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidURL(trimmed) {
                    addItem(url: trimmed, kind: .url)
                } else if !trimmed.isEmpty {
                    addItem(text: trimmed)
                }
            }
            return !strings.isEmpty
        }
    }

    @ViewBuilder
    private func statusPill(for status: LibraryItemStatus) -> some View {
        Text(statusLabel(status))
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(statusColor(status)))
    }

    private func statusLabel(_ status: LibraryItemStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .extracting: return "Extracting"
        case .synthesizing: return "Synthesizing"
        case .uploading: return "Uploading"
        case .ready: return "Ready"
        case .played: return "Played"
        case .archived: return "Archived"
        case .failed: return "Failed"
        }
    }

    private func statusColor(_ status: LibraryItemStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .extracting: return .blue
        case .synthesizing: return .blue
        case .uploading: return .orange
        case .ready: return .green
        case .played: return .secondary
        case .archived: return .secondary
        case .failed: return .red
        }
    }

    private func displayTitle(for item: LibraryItem) -> String {
        if let title = item.title, !title.isEmpty { return title }
        return deriveDisplayTitle(item)
    }

    private func deriveDisplayTitle(_ item: LibraryItem) -> String {
        if let urlString = item.sourceURL, let url = URL(string: urlString), let host = url.host {
            return host
        }
        if let rawText = item.rawText {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 50 { return trimmed }
            return String(trimmed.prefix(50)) + "…"
        }
        return "Untitled"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func isValidURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return false }
        return true
    }

    private func addURL() {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidURL(trimmed) else { return }
        addItem(url: trimmed, kind: .url)
        newURL = ""
    }

    private func addItem(url: String, kind: SourceKind) {
        let item = LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: nil,
            sourceURL: url,
            sourceKind: kind,
            rawText: nil,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil
        )
        store.add(item)
    }

    private func addItem(text: String) {
        let item = LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: nil,
            sourceURL: nil,
            sourceKind: .text,
            rawText: text,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil
        )
        store.add(item)
    }
}
