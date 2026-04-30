import AppKit
import SwiftUI

struct PanelContent: View {
    @Bindable var appState: AppState
    @Bindable var settings: TTSSettings
    @State private var hovering = false
    @State private var pressed = false
    let onRead: () -> Void
    let onStop: () -> Void
    let onSettingsChange: () -> Void

    private var expanded: Bool { hovering || appState.isPlaying }

    var body: some View {
        ZStack {
            Color.clear
            pill
                .scaleEffect(pressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
                .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering = $0 }
    }

    private var pill: some View {
        HStack(spacing: 8) {
            playButton
            if expanded {
                if appState.isPlaying {
                    Waveform()
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text("Lee selección")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .transition(.opacity)
                }
                voicePicker
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(width: expanded ? 300 : 60, height: 44, alignment: .leading)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 12)
        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var playButton: some View {
        Button(action: handleTap) {
            ZStack {
                Circle().fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.55), radius: 6, x: 0, y: 2)
                Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: appState.isPlaying ? 0 : 1)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var voicePicker: some View {
        Menu {
            ForEach(TTSProvider.allCases, id: \.self) { p in
                Button {
                    if p == .azure && !settings.azureConfigured {
                        TTSConfigWindowController.show(settings: settings) {
                            settings.provider = .azure
                            onSettingsChange()
                        }
                    } else {
                        settings.provider = p
                        onSettingsChange()
                    }
                } label: {
                    HStack {
                        if settings.provider == p { Image(systemName: "checkmark") }
                        Text(p.displayName)
                    }
                }
            }
            Divider()
            Button("Configure Azure…") {
                TTSConfigWindowController.show(settings: settings) {
                    if settings.provider == .azure { onSettingsChange() }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func handleTap() {
        if appState.isPlaying { onStop() } else { onRead() }
    }
}

private struct Waveform: View {
    @State private var phase: Double = 0
    private let bars = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
            HStack(spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: barHeight(i, t: ctx.date.timeIntervalSinceReferenceDate))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func barHeight(_ index: Int, t: TimeInterval) -> CGFloat {
        let n = Double(bars)
        let phase = t * 2.4 + Double(index) * 0.5
        let envelope = 0.5 + 0.5 * sin(Double(index) / n * .pi)
        let osc = (sin(phase) + 1) / 2
        return CGFloat(4 + envelope * osc * 16)
    }
}
