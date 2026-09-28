import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

@main
struct SelectTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Select Translate", systemImage: "character.bubble") {
            SettingsView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let popup = PopupController()
    private let monitor = SelectionMonitor()
    private var hotKey: HotKey?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: không hiện icon ở Dock (kể cả khi chạy bằng `swift run`).
        NSApp.setActivationPolicy(.accessory)

        // Lấy sẵn PATH của login shell (dùng khi gọi Claude Code CLI) để lần dịch đầu không bị chậm.
        DispatchQueue.global(qos: .utility).async { _ = ClaudeCodeClient.shellPATH }

        // Lần đầu: macOS sẽ hỏi cấp quyền Accessibility.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        monitor.onMouseDown = { [weak self] in self?.popup.hideAll() }
        monitor.onEscape = { [weak self] in self?.popup.hideAll() }
        monitor.onSelection = { [weak self] text, point in
            self?.popup.showTrigger(text: text, at: point)
        }
        monitor.start()

        // Esc khi popup đang là key window.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape), self?.popup.isVisible == true {
                self?.popup.hideAll()
                return nil
            }
            return event
        }

        // ⌥D: dịch ngay vùng đang bôi đen, không cần bấm nút.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey)) { [weak self] in
            self?.popup.translateCurrentSelection()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }
}
