import Foundation

/// State của một lần dịch, hiển thị trong ResultView.
final class TranslationSession: ObservableObject {
    enum Mode: String, Codable {
        case translate
        /// Viết lại text đang soạn thành tiếng Anh (3 phiên bản trong `replies`).
        case rewrite
    }

    struct Reply: Identifiable, Equatable, Codable {
        let id: Int
        var tone: String
        var text: String
        var meaning: String
    }

    @Published private(set) var mode = Mode.translate
    @Published private(set) var sourceText = ""
    @Published private(set) var sourceLang = ""
    @Published private(set) var translation = ""
    @Published private(set) var replies: [Reply] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var task: Task<Void, Never>?

    func start(text: String, mode: Mode) {
        task?.cancel()
        self.mode = mode
        sourceText = text
        sourceLang = ""
        translation = ""
        replies = []
        errorMessage = nil

        let settings = AppSettings.shared
        let system = switch mode {
        case .translate: Prompt.system(target: settings.targetLanguage, suggestReplies: settings.suggestReplies)
        case .rewrite: Prompt.rewrite(meaningLanguage: settings.targetLanguage)
        }
        let user = Prompt.user(text)

        let stream: AsyncThrowingStream<String, Error>
        switch settings.provider {
        case .apiKey:
            let apiKey = settings.effectiveAPIKey
            guard !apiKey.isEmpty else {
                isLoading = false
                errorMessage = ClaudeError.missingAPIKey.errorDescription
                return
            }
            stream = ClaudeClient.stream(
                ClaudeClient.Request(apiKey: apiKey, model: settings.model, system: system, user: user)
            )
        case .claudeCode:
            guard let executable = ClaudeCodeClient.locate(customPath: settings.claudeCodePath) else {
                isLoading = false
                errorMessage = ClaudeCodeError.notFound.errorDescription
                return
            }
            stream = ClaudeCodeClient.stream(executable: executable, model: settings.model, system: system, user: user)
        }
        isLoading = true

        task = Task { @MainActor [weak self] in
            var buffer = ""
            do {
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    buffer += chunk
                    self?.apply(ResponseParser.parse(buffer))
                }
                guard let self, !Task.isCancelled else { return }
                self.apply(ResponseParser.parse(buffer))
                self.isLoading = false
                if self.translation.isEmpty, self.replies.isEmpty || mode == .translate, !buffer.isEmpty {
                    // Model không theo format: hiển thị nguyên văn.
                    self.translation = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !self.translation.isEmpty || !self.replies.isEmpty {
                    HistoryStore.shared.add(
                        mode: mode, source: text, translation: self.translation, replies: self.replies
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                self?.errorMessage = error.localizedDescription
                self?.isLoading = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    private func apply(_ parsed: ResponseParser.Parsed) {
        if sourceLang != parsed.lang { sourceLang = parsed.lang }
        if translation != parsed.translation { translation = parsed.translation }
        if replies != parsed.replies { replies = parsed.replies }
    }
}
