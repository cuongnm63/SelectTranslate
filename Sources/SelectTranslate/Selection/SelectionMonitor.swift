import AppKit
import Carbon.HIToolbox

/// Theo dõi chuột toàn hệ thống để phát hiện khi người dùng bôi đen text.
/// Global monitor không nhận event của chính app này, nên click vào popup không bị tính.
final class SelectionMonitor {
    var onMouseDown: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSelection: ((SelectionReader.Selection, NSPoint) -> Void)?

    private var monitors: [Any] = []
    private var downPoint: NSPoint = .zero
    private var generation = 0
    private var pending: DispatchWorkItem?

    func start() {
        stop()
        add(.leftMouseDown) { [weak self] _ in
            guard let self else { return }
            self.generation += 1
            self.pending?.cancel()
            self.downPoint = NSEvent.mouseLocation
            self.onMouseDown?()
        }
        add(.leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
        }
        add(.keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) { self?.onEscape?() }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(monitor)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        let settings = AppSettings.shared
        guard settings.isEnabled else { return }

        // Chỉ xử lý khi có thao tác bôi đen: kéo chuột, double-click (chọn từ), triple-click (chọn dòng).
        let upPoint = NSEvent.mouseLocation
        let dragged = hypot(upPoint.x - downPoint.x, upPoint.y - downPoint.y) > 6
        guard dragged || event.clickCount >= 2 else { return }

        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.blockedBundleIDs.contains(bundleID) {
            return
        }

        let gen = generation
        let policy: SelectionReader.FallbackPolicy = settings.useCopyFallback ? .whenUnsupported : .never
        let item = DispatchWorkItem { [weak self] in
            SelectionReader.read(fallback: policy) { selection in
                guard let self, gen == self.generation,
                      let selection, selection.text.count >= settings.minChars else { return }
                self.onSelection?(selection, upPoint)
            }
        }
        pending = item
        // Đợi app đích cập nhật selection xong.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }
}
