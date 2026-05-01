// Susurro — Playback control hub shown in the menu bar dropdown during playback

import SwiftUI

struct PlaybackHubView: View {
    let bridge: MenuBarPlaybackBridge
    let onPrev: () -> Void
    let onNext: () -> Void
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onShowTranscript: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bridge.title ?? "Now Playing")
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)

            ProgressView(value: Double(bridge.currentChunk) / Double(max(bridge.chunkCount, 1)))
                .progressViewStyle(.linear)

            HStack(spacing: 12) {
                Button(action: onPrev) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.borderless)
                .disabled(bridge.currentChunk == 0)

                Button(action: onPlayPause) {
                    Image(systemName: bridge.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.borderless)
                .disabled(bridge.chunkCount == 0)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.borderless)
                .disabled(bridge.currentChunk >= bridge.chunkCount - 1)

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.borderless)
                .disabled(bridge.chunkCount == 0)
            }

            Divider()

            Button("Open transcript", action: onShowTranscript)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
