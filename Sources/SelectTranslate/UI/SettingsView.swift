import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// UI hiện khi bấm icon trên menu bar.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = HistoryStore.shared

    @State private var keyDraft = ""
    @State private var trusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var cliStatus: String?
    @State private var cliOK = true

    private let axTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !trusted { accessibilityWarning }

            section("Nguồn") {
                Picker("", selection: $settings.provider) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch settings.provider {
            case .apiKey: apiKeySection
            case .claudeCode: claudeCodeSection
            }

            section("Model") {
                Picker("", selection: $settings.model) {
                    ForEach(ModelOption.all) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
            }

            section("Dịch sang") {
                TextField("Tiếng Việt", text: $settings.targetLanguage)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Gợi ý 3 câu trả lời", isOn: $settings.suggestReplies)
                Toggle("Dùng ⌘C khi app không hỗ trợ Accessibility", isOn: $settings.useCopyFallback)
                Toggle("Mở cùng macOS", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in updateLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            section("Không hiện trong các app (bundle ID)") {
                TextField("com.apple.Terminal, ...", text: $settings.blockedAppsText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.caption)
            }

            if !history.items.isEmpty { historySection }

            Divider()

            HStack {
                Text("⌥D: dịch vùng đang bôi đen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Thoát") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onReceive(axTimer) { _ in trusted = AXIsProcessTrusted() }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        section("Anthropic API key") {
            HStack {
                SecureField(settings.apiKey.isEmpty ? "sk-ant-..." : "Đã lưu •••• \(settings.apiKey.suffix(4))", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Lưu") {
                    settings.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    keyDraft = ""
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Tạo key tại console.anthropic.com — trả tiền theo token.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var claudeCodeSection: some View {
        section("Claude Code CLI") {
            HStack {
                TextField("Tự tìm lệnh claude (để trống)", text: $settings.claudeCodePath)
                    .textFieldStyle(.roundedBorder)
                Button("Kiểm tra") { checkClaudeCode() }
            }
            TextField("CLAUDE_CONFIG_DIR (để trống = mặc định)", text: $settings.claudeConfigDir)
                .textFieldStyle(.roundedBorder)
                .help("Điền nếu bạn đăng nhập Claude Code với CLAUDE_CONFIG_DIR riêng, vd ~/.claude")
            if let cliStatus {
                Text(cliStatus)
                    .font(.caption)
                    .foregroundStyle(cliOK ? Color.green : Color.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Dùng tài khoản đã đăng nhập trong Claude Code (gói Pro/Max), không tốn tiền API. Chậm hơn ~2–4s mỗi lần.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkClaudeCode() {
        cliStatus = "Đang kiểm tra…"
        cliOK = true
        let customPath = settings.claudeCodePath
        let configDir = settings.claudeConfigDir
        DispatchQueue.global().async {
            let path = ClaudeCodeClient.locate(customPath: customPath)
            let version = path.flatMap { ClaudeCodeClient.version(executable: $0, configDir: configDir) }
            DispatchQueue.main.async {
                if let path, let version {
                    cliStatus = "\(version) — đang thử gửi 1 câu…"
                    checkLogin(executable: path, version: version)
                } else if let path {
                    cliStatus = "Tìm thấy \(path) nhưng không chạy được"
                    cliOK = false
                } else {
                    cliStatus = "Không tìm thấy lệnh claude. Cài Claude Code rồi chạy `claude` để đăng nhập."
                    cliOK = false
                }
            }
        }
    }

    /// `--version` chạy được chưa chắc đã đăng nhập được: gửi thử 1 prompt ngắn qua đúng
    /// đường dịch thật (cùng model, CLAUDE_CONFIG_DIR), dừng ngay khi có token đầu tiên.
    private func checkLogin(executable: String, version: String) {
        let stream = ClaudeCodeClient.stream(
            executable: executable, model: settings.model,
            system: "Reply with exactly: OK", user: "ping"
        )
        Task { @MainActor in
            do {
                var gotReply = false
                for try await _ in stream {
                    gotReply = true
                    break
                }
                cliOK = gotReply
                cliStatus = gotReply
                    ? "✓ \(version) — đã đăng nhập, gọi được Claude"
                    : "\(version) — Claude không trả lời"
            } catch {
                cliOK = false
                let message = error.localizedDescription
                let authFailed = ["authenticate", "OAuth", "login", "log in"].contains {
                    message.localizedCaseInsensitiveContains($0)
                }
                cliStatus = authFailed
                    ? "✗ \(message)\nĐiền CLAUDE_CONFIG_DIR khớp với lúc đăng nhập trong terminal (vd ~/.claude), hoặc chạy `claude /login`."
                    : "✗ \(message)"
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "character.bubble.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text("Select Translate").font(.headline)
                Text(settings.isEnabled ? "Bôi đen text để dịch" : "Đang tắt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var accessibilityWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Chưa có quyền Accessibility", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout.weight(.medium))
            Text("Cần quyền này để đọc text đang bôi đen. Sau khi bật, hãy thoát và mở lại app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Mở System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var historySection: some View {
        section("Gần đây") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(history.items.prefix(5)) { item in
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(item.translation, forType: .string)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.source).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                            Text(item.translation).lineLimit(1).font(.callout)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click để copy bản dịch")
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Không đổi được: \(error.localizedDescription)"
        }
    }
}
