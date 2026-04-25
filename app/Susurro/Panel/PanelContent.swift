import SwiftUI

struct PanelContent: View {
    let onRead: () -> Void

    var body: some View {
        Button(action: onRead) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .padding(8)
                .background(Color.accentColor)
                .clipShape(Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(2)
    }
}
