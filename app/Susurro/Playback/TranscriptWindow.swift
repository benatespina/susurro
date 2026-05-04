import AppKit
import NaturalLanguage
import SwiftUI

@MainActor
enum TranscriptWindowController {
    private static var windowController: NSWindowController?
    private static var bridge: TranscriptStateBridge?

    static func show(coordinator: PlaybackCoordinator, settings: TTSSettings) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let bridge = TranscriptStateBridge(coordinator: coordinator)
        self.bridge = bridge
        let view = TranscriptView(
            bridge: bridge,
            coordinator: coordinator,
            settings: settings
        )
        let hosting = NSHostingController(rootView: view)
        hosting.preferredContentSize = NSSize(width: 520, height: 600)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Now Playing"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 600))
        window.center()
        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        windowController?.close()
        windowController = nil
        bridge?.cancel()
        bridge = nil
    }
}

@MainActor
final class TranscriptStateBridge: ObservableObject {
    @Published var snapshot: PlaybackSnapshot = .empty
    private var task: Task<Void, Never>?

    init(coordinator: PlaybackCoordinator) {
        task = Task { [weak self] in
            let stream = await coordinator.snapshots()
            for await snap in stream {
                guard let self else { return }
                self.snapshot = snap
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

private struct TranscriptView: View {
    @ObservedObject var bridge: TranscriptStateBridge
    let coordinator: PlaybackCoordinator
    let settings: TTSSettings

    @State private var pronunciationDraft: PronunciationDraft?

    var body: some View {
        VStack(spacing: 0) {
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            controls
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 460, minHeight: 360)
        .sheet(item: $pronunciationDraft) { draft in
            AddPronunciationSheet(
                settings: settings,
                initial: AddPronunciationSheet.Initial(
                    word: draft.word,
                    language: draft.language,
                    currentReplacement: ""
                ),
                onSaved: { pronunciationDraft = nil },
                onCancel: { pronunciationDraft = nil }
            )
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if bridge.snapshot.chunks.isEmpty {
            VStack {
                Spacer()
                Text("Nothing playing.")
                    .foregroundStyle(.secondary)
                Text("Select text in any app and click ▶ to start.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(bridge.snapshot.chunks.enumerated()), id: \.offset) { index, chunk in
                            ChunkRow(
                                index: index,
                                text: chunk,
                                isCurrent: index == bridge.snapshot.currentChunkIndex,
                                onTap: { Task { await coordinator.seek(toChunk: index) } },
                                onFixPronunciation: { word in
                                    pronunciationDraft = PronunciationDraft(
                                        word: word,
                                        language: LanguageDetector.detect(in: chunk)
                                    )
                                }
                            )
                            .id(index)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: bridge.snapshot.currentChunkIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 16) {
            Text(progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await coordinator.seek(toChunk: max(0, bridge.snapshot.currentChunkIndex - 1)) }
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(bridge.snapshot.chunks.isEmpty || bridge.snapshot.currentChunkIndex == 0)

            Button {
                Task {
                    if bridge.snapshot.isPaused {
                        await coordinator.resume()
                    } else if bridge.snapshot.isPlaying {
                        await coordinator.pause()
                    } else if !bridge.snapshot.chunks.isEmpty {
                        await coordinator.seek(toChunk: bridge.snapshot.currentChunkIndex)
                    }
                }
            } label: {
                Image(systemName: bridge.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(bridge.snapshot.chunks.isEmpty)

            Button {
                Task { await coordinator.seek(toChunk: min(bridge.snapshot.chunks.count - 1, bridge.snapshot.currentChunkIndex + 1)) }
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(bridge.snapshot.chunks.isEmpty || bridge.snapshot.currentChunkIndex >= bridge.snapshot.chunks.count - 1)

            Button {
                Task { await coordinator.stop() }
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .disabled(bridge.snapshot.chunks.isEmpty)
        }
    }

    private var progressLabel: String {
        guard !bridge.snapshot.chunks.isEmpty else { return "—" }
        return "\(bridge.snapshot.currentChunkIndex + 1) / \(bridge.snapshot.chunks.count)"
    }
}

private struct ChunkRow: View {
    let index: Int
    let text: String
    let isCurrent: Bool
    let onTap: () -> Void
    let onFixPronunciation: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(isCurrent ? Color.accentColor : Color.clear)
                .frame(width: 3)
                .cornerRadius(1.5)

            SelectableTextView(
                text: text,
                font: NSFont.systemFont(ofSize: 15),
                textColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor,
                lineSpacing: 4,
                onTapEmpty: onTap,
                onFixPronunciation: onFixPronunciation
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }
}

private struct PronunciationDraft: Identifiable {
    let word: String
    let language: String
    var id: String { "\(language)/\(word)" }
}

enum LanguageDetector {
    static func detect(in text: String) -> String {
        guard text.count >= 10 else { return "es" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return "es" }
        return lang == .english ? "en" : "es"
    }
}
