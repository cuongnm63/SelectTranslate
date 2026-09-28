import AppKit
import SwiftUI

/// Quản lý 2 panel: nút trigger nhỏ cạnh con trỏ và popup kết quả.
final class PopupController {
    static let resultSize = NSSize(width: 440, height: 420)
    static let triggerSize = NSSize(width: 36, height: 36)

    let session = TranslationSession()

    private let triggerPanel = FloatingPanel(size: PopupController.triggerSize)
    private let resultPanel = FloatingPanel(size: PopupController.resultSize)
    private var pendingText = ""
    private var pendingPoint = NSPoint.zero
    private var autoHide: DispatchWorkItem?

    init() {
        triggerPanel.contentView = FirstMouseHostingView(
            rootView: TriggerButton { [weak self] in self?.openFromTrigger() }
        )
        resultPanel.contentView = FirstMouseHostingView(
            rootView: ResultView(session: session, onClose: { [weak self] in self?.hideAll() })
        )
    }

    var isVisible: Bool { triggerPanel.isVisible || resultPanel.isVisible }

    // MARK: - Public

    func showTrigger(text: String, at point: NSPoint) {
        pendingText = text
        pendingPoint = point
        resultPanel.orderOut(nil)
        place(triggerPanel, near: point, above: true)
        triggerPanel.orderFrontRegardless()
        scheduleAutoHide()
    }

    func showResult(text: String, at point: NSPoint) {
        cancelAutoHide()
        triggerPanel.orderOut(nil)
        session.start(text: text)
        place(resultPanel, near: point, above: false)
        resultPanel.orderFrontRegardless()
    }

    /// Dùng cho phím tắt ⌥D.
    func translateCurrentSelection() {
        SelectionReader.read(fallback: .always) { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                NSSound.beep()
                return
            }
            self.showResult(text: text, at: NSEvent.mouseLocation)
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

    // MARK: - Private

    private func openFromTrigger() {
        showResult(text: pendingText, at: pendingPoint)
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
