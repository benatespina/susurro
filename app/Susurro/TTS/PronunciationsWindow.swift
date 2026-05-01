import AppKit
import AVFoundation
import SwiftUI

@MainActor
enum PronunciationsWindowController {
    private static var windowController: NSWindowController?

    static func show(backend: BackendProcess, settings: TTSSettings) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PronunciationsView(backend: backend, settings: settings)
        let hosting = NSHostingController(rootView: view)
        hosting.preferredContentSize = NSSize(width: 560, height: 420)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pronunciations"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 420))
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        windowController?.close()
        windowController = nil
    }
}

private struct PronunciationsEntry: Identifiable, Hashable {
    let language: String
    let word: String
    let replacement: String
    var id: String { "\(language)/\(word)" }
}

private struct PronunciationsView: View {
    let backend: BackendProcess
    let settings: TTSSettings

    @State private var entries: [PronunciationsEntry] = []
    @State private var loading: Bool = false
    @State private var errorMessage: String?
    @State private var showingAdd: Bool = false
    @State private var editingEntry: PronunciationsEntry?
    @State private var previewingId: String?
    @StateObject private var rowAudio = PreviewAudio()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Table(entries) {
                TableColumn("Lang") { entry in
                    Text(entry.language.uppercased())
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 50, ideal: 50, max: 60)
                TableColumn("Word") { entry in
                    Text(entry.word)
                }
                .width(min: 100, ideal: 140)
                TableColumn("Replacement (SSML)") { entry in
                    Text(entry.replacement)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("") { entry in
                    Button {
                        Task { await preview(entry) }
                    } label: {
                        if previewingId == entry.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.provider != .azure || previewingId != nil)
                    .help(settings.provider == .azure ? "Preview" : "Azure required")
                }
                .width(34)
                TableColumn("") { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit")
                }
                .width(34)
                TableColumn("") { entry in
                    Button(role: .destructive) {
                        Task { await delete(entry) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .width(34)
            }
            .frame(minHeight: 220)

            footer
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .task { await reload() }
        .onDisappear { rowAudio.stop() }
        .sheet(isPresented: $showingAdd) {
            AddPronunciationSheet(
                backend: backend,
                settings: settings,
                initial: nil,
                onSaved: {
                    showingAdd = false
                    Task { await reload() }
                },
                onCancel: { showingAdd = false }
            )
        }
        .sheet(item: $editingEntry) { entry in
            AddPronunciationSheet(
                backend: backend,
                settings: settings,
                initial: AddPronunciationSheet.Initial(
                    word: entry.word,
                    language: entry.language,
                    currentReplacement: entry.replacement
                ),
                onSaved: {
                    editingEntry = nil
                    Task { await reload() }
                },
                onCancel: { editingEntry = nil }
            )
        }
    }

    private func preview(_ entry: PronunciationsEntry) async {
        guard settings.provider == .azure else {
            errorMessage = "Switch to the Azure provider to preview."
            return
        }
        previewingId = entry.id
        defer { previewingId = nil }
        guard case .ready(let client) = await backend.state else {
            errorMessage = "Backend not ready."
            return
        }
        do {
            let mp3 = try await client.previewSSML(
                ssml: entry.replacement, language: entry.language
            )
            await rowAudio.play(mp3: mp3)
        } catch {
            errorMessage = "Preview failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pronunciations")
                    .font(.headline)
                Text("Custom replacements applied during Azure TTS synthesis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            providerBadge
        }
    }

    @ViewBuilder
    private var providerBadge: some View {
        let isAzure = settings.provider == .azure
        HStack(spacing: 4) {
            Circle()
                .fill(isAzure ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(isAzure ? "Azure active" : "Azure required for preview & runtime")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(Pronunciations.fileURL)
            } label: {
                Label("Open JSON…", systemImage: "doc.text")
            }
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            Button {
                showingAdd = true
            } label: {
                Label("Add…", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        guard case .ready(let client) = await backend.state else {
            errorMessage = "Backend not ready."
            return
        }
        do {
            let raw = try await client.listPronunciations()
            var rows: [PronunciationsEntry] = []
            for (language, dict) in raw {
                for (word, replacement) in dict {
                    rows.append(PronunciationsEntry(
                        language: language, word: word, replacement: replacement
                    ))
                }
            }
            rows.sort { ($0.language, $0.word.lowercased()) < ($1.language, $1.word.lowercased()) }
            entries = rows
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func delete(_ entry: PronunciationsEntry) async {
        guard case .ready(let client) = await backend.state else {
            errorMessage = "Backend not ready."
            return
        }
        do {
            try await client.deletePronunciation(language: entry.language, word: entry.word)
            await reload()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

private struct AddPronunciationSheet: View {
    struct Initial {
        let word: String
        let language: String
        let currentReplacement: String
    }

    let backend: BackendProcess
    let settings: TTSSettings
    let initial: Initial?
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var word: String = ""
    @State private var language: String = "es"
    @State private var candidates: [PronunciationCandidate] = []
    @State private var selected: PronunciationCandidate?
    @State private var loadingCandidates: Bool = false
    @State private var saving: Bool = false
    @State private var errorMessage: String?
    @State private var previewing: PronunciationCandidate?
    @State private var didInitialize: Bool = false
    @StateObject private var audio = PreviewAudio()

    private var isEditing: Bool { initial != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing ? "Edit pronunciation" : "Add pronunciation")
                .font(.headline)

            HStack {
                Picker("Language", selection: $language) {
                    Text("Español").tag("es")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(isEditing)

                TextField("Word (e.g. framework)", text: $word)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isEditing)
                    .onSubmit { Task { await loadCandidates() } }

                Button {
                    Task { await loadCandidates() }
                } label: {
                    if loadingCandidates {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isEditing ? "Refresh" : "Generate")
                    }
                }
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty || loadingCandidates)
                .keyboardShortcut(.return, modifiers: [])
            }

            if settings.provider != .azure {
                Text("Switch to Azure to preview candidates. Entries still get saved and will activate when Azure is enabled.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if candidates.isEmpty {
                emptyHint
            } else {
                candidatesList
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil || saving)
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            if let initial {
                word = initial.word
                language = initial.language
                let current = PronunciationCandidate(
                    kind: "current",
                    label: "Current saved replacement",
                    ssml: initial.currentReplacement
                )
                candidates = [current]
                selected = current
                Task { await loadCandidates(preserveCurrent: current) }
            }
        }
        .onDisappear { audio.stop() }
    }

    @ViewBuilder
    private var emptyHint: some View {
        VStack {
            Spacer()
            Text("Type a word and press Generate to see candidate pronunciations.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var candidatesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(candidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        isSelected: selected?.id == candidate.id,
                        isPlaying: previewing?.id == candidate.id,
                        canPreview: settings.provider == .azure,
                        onSelect: { selected = candidate },
                        onPreview: { Task { await preview(candidate) } }
                    )
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func loadCandidates(preserveCurrent: PronunciationCandidate? = nil) async {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loadingCandidates = true
        defer { loadingCandidates = false }
        errorMessage = nil
        guard case .ready(let client) = await backend.state else {
            errorMessage = "Backend not ready."
            return
        }
        do {
            let generated = try await client.pronunciationCandidates(word: trimmed, language: language)
            if let current = preserveCurrent {
                let dedup = generated.filter { $0.ssml != current.ssml }
                candidates = [current] + dedup
                selected = current
            } else {
                candidates = generated
                selected = generated.first
            }
        } catch {
            errorMessage = "Could not generate candidates: \(error.localizedDescription)"
        }
    }

    private func preview(_ candidate: PronunciationCandidate) async {
        guard settings.provider == .azure else {
            errorMessage = "Switch to the Azure provider to preview."
            return
        }
        previewing = candidate
        defer { previewing = nil }
        guard case .ready(let client) = await backend.state else {
            errorMessage = "Backend not ready."
            return
        }
        do {
            let mp3 = try await client.previewSSML(ssml: candidate.ssml, language: language)
            await audio.play(mp3: mp3)
        } catch {
            errorMessage = "Preview failed: \(error.localizedDescription)"
        }
    }

    private func save() async {
        guard let selected else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        defer { saving = false }
        errorMessage = nil
        guard case .ready(let client) = await backend.state else {
            errorMessage = "Backend not ready."
            return
        }
        do {
            try await client.upsertPronunciation(
                language: language, word: trimmed, replacement: selected.ssml
            )
            onSaved()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

private struct CandidateRow: View {
    let candidate: PronunciationCandidate
    let isSelected: Bool
    let isPlaying: Bool
    let canPreview: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .onTapGesture(perform: onSelect)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.label)
                    .font(.callout)
                Text(candidate.ssml)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            Button(action: onPreview) {
                if isPlaying {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!canPreview || isPlaying)
            .help(canPreview ? "Preview with Azure voice" : "Azure provider required")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

@MainActor
private final class PreviewAudio: ObservableObject {
    private var player: AVAudioPlayer?

    func play(mp3: Data) async {
        do {
            let p = try AVAudioPlayer(data: mp3)
            player = p
            p.prepareToPlay()
            p.play()
            while p.isPlaying {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            AppLogger.playback.error("preview audio failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
