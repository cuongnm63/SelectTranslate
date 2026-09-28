import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case badResponse
    case http(Int, String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Chưa có API key. Bấm icon trên menu bar để nhập Anthropic API key."
        case .badResponse:
            return "Phản hồi không hợp lệ từ Claude API."
        case .http(let code, let message):
            return "Lỗi \(code): \(message)"
        case .api(let message):
            return message
        }
    }
}

/// Gọi Claude Messages API với streaming (SSE).
enum ClaudeClient {
    struct Request {
        var apiKey: String
        var model: String
        var system: String
        var user: String
        var maxTokens: Int = 2048
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Trả về từng đoạn text khi Claude đang sinh.
    static func stream(_ request: Request) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = 60
                    urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

                    let body: [String: Any] = [
                        "model": request.model,
                        "max_tokens": request.maxTokens,
                        "stream": true,
                        "system": request.system,
                        "messages": [["role": "user", "content": request.user]],
                    ]
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }

                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw ClaudeError.http(http.statusCode, errorMessage(from: data))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = json.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        switch event["type"] as? String {
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String
                            throw ClaudeError.api(message ?? "Claude API trả về lỗi.")
                        case "message_stop":
                            continuation.finish()
                            return
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = obj["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Không rõ lỗi"
    }
}
