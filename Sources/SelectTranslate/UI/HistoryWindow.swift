import AppKit
import SwiftUI

/// Cửa sổ xem toàn bộ lịch sử (mở từ mục "Gần đây" trong Settings).
final class HistoryWindowController {
    static let shared = HistoryWindowController()

    private var window: NSWindow?

    /// Mở cửa sổ, cuộn tới `itemID` nếu có.
    func show(itemID: UUID? = nil) {
        let root = HistoryView(focus: itemID.map { HistoryView.Focus(id: $0) })
        if let host = window?.contentView as? NSHostingView<HistoryView> {
            host.rootView = root
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Lịch sử — Select Translate"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.center()
            window.setFrameAutosaveName("HistoryWindow")
            self.window = window
        }
        // App chỉ ở menu bar (accessory) → phải kích hoạt thì cửa sổ mới lên trên cùng.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HistoryView: View {
    /// Mỗi lần mở tạo token mới để click lại cùng một mục vẫn cuộn tới nó.
    struct Focus: Equatable {
        let id: UUID
        let token = UUID()
    }

    var focus: Focus?
    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                Text("Chưa có lịch sử")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(store.items) { item in
                                HistoryRow(item: item, highlighted: item.id == focus?.id)
                                    .id(item.id)
                            }
                        }
                        .padding(16)
                    }
                    .task(id: focus) {
                        if let focus { proxy.scrollTo(focus.id, anchor: .top) }
                    }
                }
            }
            Divider()
            HStack {
                Text("\(store.items.count) mục")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Xoá lịch sử", role: .destructive) { store.clear() }
                    .disabled(store.items.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

private struct HistoryRow: View {
    let item: HistoryStore.Item
    let highlighted: Bool

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(
                    item.mode == .rewrite ? "Viết lại" : "Dịch",
                    systemImage: item.mode == .rewrite ? "wand.and.stars" : "character.bubble"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                Text(item.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(item.source)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !item.translation.isEmpty {
                CopyableBlock(text: item.translation) {
                    Text(item.translation)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(item.replies) { reply in
                ReplyRow(reply: reply)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: shape)
        .overlay(shape.strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: highlighted ? 2 : 1))
    }
}
