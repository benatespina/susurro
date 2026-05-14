import SwiftUI

struct LibraryView: View {
    @Bindable var store: LibraryStore
    var synthesizer: LibrarySynthesizer
    var synthesisState: LibrarySynthesisState
    var onSynthesize: (UUID) -> Void

    @State private var newURL: String = ""
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if synthesisState.depth > 0 {
                synthesisBanner
            }
            Divider()
            content
        }
    }

    // MARK: - Subviews

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
    private var synthesisBanner: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
            Text("Synthesizing \(synthesisState.depth) item\(synthesisState.depth == 1 ? "" : "s")…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        Divider()
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
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle(for: item))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(relativeDate(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                rowTrailing(for: item)
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

    // MARK: - Per-row trailing controls

    @ViewBuilder
    private func rowTrailing(for item: LibraryItem) -> some View {
        switch item.status {
        case .pending:
            Button("Synthesize now") {
                onSynthesize(item.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .extracting:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Extracting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .synthesizing(let progress):
            HStack(spacing: 6) {
                if let p = progress {
                    ProgressView(value: p, total: 1.0)
                        .frame(width: 60)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                }
                Text("Synthesizing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .uploading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Uploading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            VStack(alignment: .trailing, spacing: 2) {
                if let dur = item.durationSeconds {
                    Text(formattedDuration(dur))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let size = item.byteSize {
                    Text(formattedSize(size))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

        case .played:
            Text("Played")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary))

        case .archived:
            Text("Archived")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary))

        case .failed(let reason):
            HStack(spacing: 4) {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button("Retry") {
                    onSynthesize(item.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Formatting helpers

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return "\(m)m \(String(format: "%02d", s))s"
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Existing helpers (unchanged)

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
        onSynthesize(item.id)
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
        onSynthesize(item.id)
    }
}
