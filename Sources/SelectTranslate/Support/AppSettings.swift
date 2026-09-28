import Foundation

struct ModelOption: Identifiable, Hashable {
    let id: String
    let label: String

    static let all: [ModelOption] = [
        ModelOption(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5 — nhanh, rẻ"),
        ModelOption(id: "claude-sonnet-5", label: "Sonnet 5 — cân bằng"),
        ModelOption(id: "claude-opus-5-5", label: "Opus 5.5 — chất lượng cao nhất"),
    ]
    static let defaultID = all[0].id
}

enum Provider: String, CaseIterable, Identifiable {
    case apiKey
    case claudeCode

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apiKey: return "API key"
        case .claudeCode: return "Claude Code"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private static let apiKeyAccount = "anthropic-api-key"

    let minChars = 2

    /// Nguồn gọi Claude: API key (trả theo token) hoặc Claude Code CLI (gói Pro/Max).
    @Published var provider: Provider {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    /// Đường dẫn tới `claude`; để trống = tự tìm.
    @Published var claudeCodePath: String {
        didSet { defaults.set(claudeCodePath, forKey: "claudeCodePath") }
    }
    @Published var apiKey: String {
        didSet { Keychain.write(apiKey, account: Self.apiKeyAccount) }
    }
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "isEnabled") }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: "model") }
    }
    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: "targetLanguage") }
    }
    @Published var suggestReplies: Bool {
        didSet { defaults.set(suggestReplies, forKey: "suggestReplies") }
    }
    @Published var useCopyFallback: Bool {
        didSet { defaults.set(useCopyFallback, forKey: "useCopyFallback") }
    }
    /// Bundle ID các app không muốn hiện nút dịch, cách nhau bởi dấu phẩy hoặc xuống dòng.
    @Published var blockedAppsText: String {
        didSet { defaults.set(blockedAppsText, forKey: "blockedAppsText") }
    }

    private init() {
        let defaults = UserDefaults.standard
        // Lần đầu: nếu máy đã cài Claude Code thì mặc định dùng nó.
        provider = Provider(rawValue: defaults.string(forKey: "provider") ?? "")
            ?? (ClaudeCodeClient.locate(customPath: "", useShellPath: false) != nil ? .claudeCode : .apiKey)
        claudeCodePath = defaults.string(forKey: "claudeCodePath") ?? ""
        apiKey = Keychain.read(account: Self.apiKeyAccount) ?? ""
        isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        model = defaults.string(forKey: "model") ?? ModelOption.defaultID
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? "Tiếng Việt"
        suggestReplies = defaults.object(forKey: "suggestReplies") as? Bool ?? true
        useCopyFallback = defaults.object(forKey: "useCopyFallback") as? Bool ?? true
        blockedAppsText = defaults.string(forKey: "blockedAppsText") ?? [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.1password.1password",
            "com.apple.keychainaccess",
        ].joined(separator: ", ")
    }

    /// Key trong Keychain, hoặc biến môi trường ANTHROPIC_API_KEY khi chạy bằng `swift run`.
    var effectiveAPIKey: String {
        if !apiKey.isEmpty { return apiKey }
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    var blockedBundleIDs: Set<String> {
        Set(
            blockedAppsText
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    struct Item: Identifiable {
        let id = UUID()
        let source: String
        let translation: String
    }

    @Published private(set) var items: [Item] = []

    func add(source: String, translation: String) {
        items.insert(Item(source: source, translation: translation), at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }
    }

    func clear() { items.removeAll() }
}
