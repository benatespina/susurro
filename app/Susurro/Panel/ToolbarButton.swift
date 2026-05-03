import SwiftUI

struct ToolbarButton: View {
    let systemImage: String
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPrimary ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(buttonBackground)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .scaleEffect(pressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
        .onHover { hovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var buttonBackground: Color {
        if isPrimary {
            return hovered ? Color.accentColor.opacity(0.85) : Color.accentColor
        }
        return hovered ? Color.primary.opacity(0.12) : Color.clear
    }
}
