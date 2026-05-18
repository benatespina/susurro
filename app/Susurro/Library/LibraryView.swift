import SwiftUI

struct LibraryView: View {
    @Bindable var store: LibraryStore
    var synthesizer: LibrarySynthesizer
    var synthesisState: LibrarySynthesisState
    var publisher: (any LibraryPublishing)?
    var player: LibraryPlayer
    var settings: LibrarySettings
    var onSynthesize: (UUID) -> Void
    var onMarkPlayed: (UUID) -> Void
    var onDelete: ((UUID) -> Void)? = nil

    @State private var newURL: String = ""
    @State private var selection: UUID?
    @State private var feedConfig: DriveConfig?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if synthesisState.depth > 0 {
                synthesisBanner
            }
            driveStatusBanner
            Divider()
            content
        }
        .onAppear { feedConfig = DriveConfig.load() }
        .onChange(of: store.items.map(\.driveFileID)) { _, _ in
            // Auto-publish writes feedFileID to Keychain outside this view; re-read
            // so the feed-URL banner refreshes the moment publishing completes.
            feedConfig = DriveConfig.load()
        }
        .sheet(isPresented: $showingSettings, onDismiss: { feedConfig = DriveConfig.load() }) {
            LibrarySettingsSheet(settings: settings, publisher: publisher, store: store)
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
            Spacer()
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
    private var driveStatusBanner: some View {
        if let feedURL = feedConfig?.feedURL() {
            HStack(spacing: 6) {
                Text("Feed URL:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(feedURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Copy feed URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(feedURL.absoluteString, forType: .string)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        } else if publisher != nil {
            HStack(spacing: 6) {
                Text("Configure Google Drive to publish")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle(for: item))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(item.status == .archived ? Color.secondary : Color.primary)
                        Text(relativeDate(item.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    rowTrailing(for: item)
                }
                // Scrubber — only visible when this item is currently playing.
                if player.nowPlayingID == item.id && player.duration > 0 {
                    scrubber(for: item)
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    deleteItem(item.id)
                }
            }
        }
        .onDeleteCommand {
            if let id = selection {
                deleteItem(id)
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
    private func scrubber(for item: LibraryItem) -> some View {
        HStack(spacing: 8) {
            Text(formattedDuration(player.currentTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            Text(formattedDuration(player.duration))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Button(action: {
                player.setRate(PlaybackSpeed.next(from: player.playbackRate))
            }) {
                Text(PlaybackSpeed.formatted(player.playbackRate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Playback speed (click to cycle)")
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
            inProgressLabel("Extracting")

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
            inProgressLabel("Uploading")

        case .ready:
            HStack(spacing: 6) {
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
                playPauseButton(for: item)
                Button("Mark played") {
                    onMarkPlayed(item.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                rePublishButton(for: item)
            }

        case .played:
            HStack(spacing: 6) {
                if item.audioFilename != nil {
                    playPauseButton(for: item)
                }
                Text("Played ✓")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary))
                rePublishButton(for: item)
            }

        case .archived:
            Text("Archived")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(nsColor: .separatorColor)))

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
                if item.audioFilename != nil && store.audioURL(for: item) != nil {
                    rePublishButton(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func playPauseButton(for item: LibraryItem) -> some View {
        let isThisItemPlaying = player.nowPlayingID == item.id && player.isPlaying
        Button {
            if isThisItemPlaying {
                player.pause()
            } else if player.nowPlayingID == item.id {
                player.resume()
            } else {
                if let audioURL = store.audioURL(for: item) {
                    player.play(item: item, audioURL: audioURL)
                }
            }
        } label: {
            Image(systemName: isThisItemPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(store.audioURL(for: item) == nil)
    }

    @ViewBuilder
    private func rePublishButton(for item: LibraryItem) -> some View {
        if let pub = publisher, feedConfig?.hasFolder == true {
            Button("Re-publish") {
                Task { try? await pub.publish(itemID: item.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func inProgressLabel(_ label: String) -> some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func deleteItem(_ id: UUID) {
        (onDelete ?? { store.remove(id: $0) })(id)
    }

    private func addURL() {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidURL(trimmed) else { return }
        addItem(url: trimmed, kind: .url)
        newURL = ""
    }

    private func addItem(url: String, kind: SourceKind) {
        enqueueNewItem(sourceURL: url, sourceKind: kind, rawText: nil, title: nil)
    }

    private func addItem(text: String) {
        enqueueNewItem(sourceURL: nil, sourceKind: .text, rawText: text, title: nil)
    }

    private func enqueueNewItem(
        sourceURL: String?,
        sourceKind: SourceKind,
        rawText: String?,
        title: String?
    ) {
        let item = LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: title,
            sourceURL: sourceURL,
            sourceKind: sourceKind,
            rawText: rawText,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
        store.add(item)
        onSynthesize(item.id)
    }
}

// MARK: - LibrarySettingsSheet

private struct LibrarySettingsSheet: View {
    @Bindable var settings: LibrarySettings
    let publisher: (any LibraryPublishing)?
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var orphanCount: Int = 0
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Library Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Played items TTL: \(settings.playedTTLDays) days")
                    .font(.subheadline)
                Slider(
                    value: Binding(
                        get: { Double(settings.playedTTLDays) },
                        set: { settings.playedTTLDays = Int($0) }
                    ),
                    in: 1...365,
                    step: 1
                )
                Text("Items marked as played are automatically archived after this many days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Auto-publish after synthesis", isOn: $settings.autoPublishOnSynthesize)

            Button {
                guard let pub = publisher else { return }
                isSyncing = true
                Task {
                    _ = await pub.sync()
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    if isSyncing { ProgressView().scaleEffect(0.7).frame(width: 14, height: 14) }
                    Text("Sync now (\(orphanCount) pending)")
                }
            }
            .disabled(publisher == nil || isSyncing)
            .task {
                if let pub = publisher { orphanCount = await pub.orphanCount() }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
