import SwiftUI

struct ToolbarButton<Content: View>: View {
    var isPrimary: Bool = false
    let action: () -> Void
    let content: Content

    @State private var hovered = false
    @State private var pressed = false

    init(
        isPrimary: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isPrimary = isPrimary
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
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

extension ToolbarButton where Content == AnyView {
    init(systemImage: String, isPrimary: Bool = false, action: @escaping () -> Void) {
        self.init(isPrimary: isPrimary, action: action) {
            AnyView(
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            )
        }
    }
}
