import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Quản lý 2 panel: nút trigger nhỏ cạnh con trỏ và popup kết quả.
final class PopupController {
    static let resultSize = NSSize(width: 440, height: 420)
    static func triggerSize(showRewrite: Bool) -> NSSize {
        NSSize(width: showRewrite ? 68 : 36, height: 36)
    }

    let session = TranslationSession()

    private let triggerPanel = FloatingPanel(size: PopupController.triggerSize(showRewrite: false))
    private let resultPanel = FloatingPanel(size: PopupController.resultSize)
    private var triggerHost: FirstMouseHostingView<TriggerButton>!
    private var pendingText = ""
    private var pendingPoint = NSPoint.zero
    /// App chứa vùng chọn — kích hoạt lại trước khi dán bản viết lại.
    private var sourceApp: NSRunningApplication?
    private var autoHide: DispatchWorkItem?

    init() {
        triggerHost = FirstMouseHostingView(rootView: makeTrigger(showRewrite: false))
        triggerPanel.contentView = triggerHost
        resultPanel.contentView = FirstMouseHostingView(
            rootView: ResultView(
                session: session,
                onClose: { [weak self] in self?.hideAll() },
                onReplace: { [weak self] text in self?.replaceSelection(with: text) }
            )
        )
    }

    var isVisible: Bool { triggerPanel.isVisible || resultPanel.isVisible }

    // MARK: - Public

    func showTrigger(selection: SelectionReader.Selection, at point: NSPoint) {
        pendingText = selection.text
        pendingPoint = point
        sourceApp = NSWorkspace.shared.frontmostApplication
        resultPanel.orderOut(nil)
        triggerHost.rootView = makeTrigger(showRewrite: selection.editable)
        triggerPanel.setContentSize(Self.triggerSize(showRewrite: selection.editable))
        place(triggerPanel, near: point, above: true)
        triggerPanel.orderFrontRegardless()
        scheduleAutoHide()
    }

    func showResult(text: String, mode: TranslationSession.Mode, at point: NSPoint) {
        cancelAutoHide()
        triggerPanel.orderOut(nil)
        session.start(text: text, mode: mode)
        place(resultPanel, near: point, above: false)
        resultPanel.orderFrontRegardless()
    }

    /// Dùng cho phím tắt ⌥D (dịch) / ⌥R (viết lại). Người dùng chủ động bấm nên luôn cho viết lại,
    /// kể cả khi đọc bằng ⌘C (app không hỗ trợ AX) — "Thay thế" dán bằng ⌘V nên vẫn chạy được.
    func openCurrentSelection(mode: TranslationSession.Mode) {
        SelectionReader.read(fallback: .always) { [weak self] selection in
            guard let self else { return }
            guard let selection else {
                NSSound.beep()
                return
            }
            self.sourceApp = NSWorkspace.shared.frontmostApplication
            self.showResult(text: selection.text, mode: mode, at: NSEvent.mouseLocation)
        }
    }

    func hideAll() {
        cancelAutoHide()
        triggerPanel.orderOut(nil)
        if resultPanel.isVisible {
            resultPanel.orderOut(nil)
            session.cancel()
        }
    }

    /// Dán đè bản viết lại vào vùng đang chọn: ⌘V rồi khôi phục clipboard cũ. Dùng ⌘V thay vì
    /// ghi kAXSelectedText vì Chrome/Electron hay báo thành công mà không đổi gì.
    func replaceSelection(with text: String) {
        let app = sourceApp
        hideAll()
        // Popup có thể đã thành key window (khi click vào text) → trả focus về app nguồn.
        if #available(macOS 14, *) {
            app?.activate()
        } else {
            app?.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let pasteboard = NSPasteboard.general
            let snapshot = PasteboardSnapshot(pasteboard)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            KeyPoster.press(key: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                snapshot.restore(to: pasteboard)
            }
        }
    }

    // MARK: - Private

    private func makeTrigger(showRewrite: Bool) -> TriggerButton {
        TriggerButton(
            showRewrite: showRewrite,
            onTranslate: { [weak self] in self?.openFromTrigger(mode: .translate) },
            onRewrite: { [weak self] in self?.openFromTrigger(mode: .rewrite) }
        )
    }

    private func openFromTrigger(mode: TranslationSession.Mode) {
        showResult(text: pendingText, mode: mode, at: pendingPoint)
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        let item = DispatchWorkItem { [weak self] in self?.triggerPanel.orderOut(nil) }
        autoHide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    private func cancelAutoHide() {
        autoHide?.cancel()
        autoHide = nil
    }

    /// Đặt panel cạnh con trỏ, luôn nằm gọn trong màn hình chứa con trỏ.
    private func place(_ panel: NSPanel, near point: NSPoint, above: Bool) {
        let size = panel.frame.size
        let gap: CGFloat = 10
        var origin = above
            ? NSPoint(x: point.x + 4, y: point.y + gap)
            : NSPoint(x: point.x - 24, y: point.y - size.height - gap)

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            if above, origin.y + size.height > frame.maxY { origin.y = point.y - size.height - gap }
            if !above, origin.y < frame.minY { origin.y = point.y + gap }
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
            origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }
}
