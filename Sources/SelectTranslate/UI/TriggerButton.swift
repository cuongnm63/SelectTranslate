import SwiftUI

/// Nút tròn nhỏ hiện cạnh vùng bôi đen. Trong ô input có thêm nút "Viết lại bằng tiếng Anh".
struct TriggerButton: View {
    var showRewrite: Bool
    var onTranslate: () -> Void
    var onRewrite: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CircleButton(icon: "character.bubble.fill", help: "Dịch với Claude (⌥D)", action: onTranslate)
            if showRewrite {
                CircleButton(icon: "wand.and.stars", help: "Viết lại hay hơn bằng tiếng Anh (⌥R)", action: onRewrite)
            }
        }
        .frame(
            width: PopupController.triggerSize(showRewrite: showRewrite).width,
            height: PopupController.triggerSize(showRewrite: showRewrite).height
        )
    }
}

private struct CircleButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
                .scaleEffect(hovering ? 1.1 : 1)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}
