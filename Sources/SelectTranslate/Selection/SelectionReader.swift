import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Đọc text đang được bôi đen ở app đang active.
/// 1) Accessibility API (kAXSelectedTextAttribute) — không đụng clipboard.
/// 2) Fallback: giả lập ⌘C, đọc clipboard rồi khôi phục clipboard cũ.
enum SelectionReader {
    enum FallbackPolicy {
        case never
        /// Chỉ dùng ⌘C khi app không hỗ trợ AX (Electron, một số app Java...).
        case whenUnsupported
        /// Luôn thử ⌘C nếu AX không trả về text (dùng cho phím tắt — người dùng chủ động).
        case always
    }

    private enum AXResult {
        case text(String)
        case empty
        case unsupported
    }

    static func read(fallback: FallbackPolicy, completion: @escaping (String?) -> Void) {
        let result = readViaAccessibility()
        switch (result, fallback) {
        case (.text(let text), _):
            completion(text)
        case (.unsupported, .whenUnsupported), (_, .always):
            readViaCopy(completion: completion)
        default:
            completion(nil)
        }
    }

    private static func readViaAccessibility() -> AXResult {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return .unsupported }

        let focused = focusedRef as! AXUIElement
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String
        else { return .unsupported }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .empty : .text(trimmed)
    }

    private static func readViaCopy(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount

        KeyPoster.press(key: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard pasteboard.changeCount != before else {
                completion(nil)
                return
            }
            let text = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.restore(to: pasteboard)
            if let text, !text.isEmpty {
                completion(text)
            } else {
                completion(nil)
            }
        }
    }
}

enum KeyPoster {
    static func press(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Lưu toàn bộ nội dung clipboard (mọi kiểu dữ liệu) để khôi phục sau khi đọc bằng ⌘C.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
