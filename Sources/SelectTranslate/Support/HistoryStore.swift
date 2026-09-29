import Foundation

/// Lịch sử dịch / viết lại, lưu JSON trong Application Support để giữ qua các lần mở app.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let limit = 100

    struct Item: Identifiable, Codable, Equatable {
        var id = UUID()
        var date = Date()
        let mode: TranslationSession.Mode
        let source: String
        let translation: String
        let replies: [TranslationSession.Reply]

        /// Dòng xem nhanh: bản dịch, hoặc bản viết lại chính.
        var preview: String {
            translation.isEmpty ? (replies.first?.text ?? "") : translation
        }
    }

    @Published private(set) var items: [Item] = [] {
        didSet { save() }
    }

    private static let fileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SelectTranslate", isDirectory: true)
        .appendingPathComponent("history.json")

    private init() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            items = try Self.decoder.decode([Item].self, from: data)
        } catch {
            NSLog("SelectTranslate: không đọc được lịch sử: \(error)")
        }
    }

    func add(mode: TranslationSession.Mode, source: String, translation: String, replies: [TranslationSession.Reply]) {
        items.insert(Item(mode: mode, source: source, translation: translation, replies: replies), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    func clear() { items.removeAll() }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Self.encoder.encode(items).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("SelectTranslate: không lưu được lịch sử: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
