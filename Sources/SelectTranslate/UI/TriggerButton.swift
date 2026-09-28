import SwiftUI

/// Nút tròn nhỏ hiện cạnh vùng bôi đen.
struct TriggerButton: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "character.bubble.fill")
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
        .help("Dịch với Claude (⌥D)")
        .frame(width: PopupController.triggerSize.width, height: PopupController.triggerSize.height)
    }
}
