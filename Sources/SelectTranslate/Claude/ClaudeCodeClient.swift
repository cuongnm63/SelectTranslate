import Foundation

enum ClaudeCodeError: LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Không tìm thấy Claude Code CLI. Cài Claude Code, chạy `claude` một lần để đăng nhập, hoặc nhập đường dẫn tới lệnh `claude` trong Settings."
        case .failed(let message):
            return "Claude Code: \(message)"
        }
    }
}

/// Gọi Claude qua Claude Code CLI (`claude -p`) — dùng tài khoản đã đăng nhập (gói Pro/Max).
enum ClaudeCodeClient {
    static let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// PATH của login shell (app mở từ Finder không có PATH của terminal).
    static let shellPATH: String = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "printf %s \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return defaultPATH }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? defaultPATH : "\(path):\(defaultPATH)"
    }()

    /// Tìm file thực thi `claude`.
    static func locate(customPath: String, useShellPath: Bool = true) -> String? {
        let fm = FileManager.default
        let custom = (customPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if !custom.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? custom : nil
        }

        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
        // nvm: ~/.nvm/versions/node/<version>/bin/claude
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            candidates += versions.sorted(by: >).map { "\(nvmDir)/\($0)/bin/claude" }
        }
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return hit
        }

        guard useShellPath else { return nil }
        for dir in shellPATH.split(separator: ":") {
            let path = "\(dir)/claude"
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// `claude --version` — dùng cho nút "Kiểm tra" trong Settings. Chạy blocking, gọi từ background.
    static func version(executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        process.environment = environment(for: executable)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stream text từ `claude -p --output-format stream-json --include-partial-messages`.
    static func stream(executable: String, model: String, system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [
                "-p", user,
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--model", model,
                "--system-prompt", system,
                "--max-turns", "1",
            ]
            process.environment = environment(for: executable)
            // Thư mục tạm: tránh Claude Code đọc CLAUDE.md / settings của project nào đó.
            process.currentDirectoryURL = FileManager.default.temporaryDirectory

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: ClaudeCodeError.failed(error.localizedDescription))
                return
            }

            let errBox = DataBox()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            DispatchQueue.global().async {
                var yielded = false
                var resultError: String?

                func handle(_ line: Data) {
                    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                    switch obj["type"] as? String {
                    case "stream_event":
                        if let event = obj["event"] as? [String: Any],
                           event["type"] as? String == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            yielded = true
                            continuation.yield(text)
                        }
                    case "assistant":
                        // CLI cũ không hỗ trợ partial messages: lấy cả message một lần.
                        guard !yielded,
                              let message = obj["message"] as? [String: Any],
                              let content = message["content"] as? [[String: Any]] else { return }
                        let text = content.compactMap { $0["text"] as? String }.joined()
                        if !text.isEmpty {
                            yielded = true
                            continuation.yield(text)
                        }
                    case "result":
                        let isError = (obj["is_error"] as? Bool) == true || (obj["subtype"] as? String) != "success"
                        if isError {
                            resultError = (obj["result"] as? String) ?? (obj["subtype"] as? String) ?? "Lỗi không rõ"
                        } else if !yielded, let text = obj["result"] as? String {
                            yielded = true
                            continuation.yield(text)
                        }
                    default:
                        break
                    }
                }

                let reader = stdout.fileHandleForReading
                var buffer = Data()
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = buffer.subdata(in: buffer.startIndex..<newline)
                        buffer.removeSubrange(buffer.startIndex...newline)
                        if !line.isEmpty { handle(line) }
                    }
                }
                if !buffer.isEmpty { handle(buffer) }

                process.waitUntilExit()
                group.wait()

                if let resultError {
                    continuation.finish(throwing: ClaudeCodeError.failed(resultError))
                } else if process.terminationReason == .uncaughtSignal {
                    continuation.finish(throwing: CancellationError())
                } else if process.terminationStatus != 0, !yielded {
                    let message = String(data: errBox.data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.finish(throwing: ClaudeCodeError.failed(
                        message.isEmpty ? "thoát với mã \(process.terminationStatus)" : message
                    ))
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }
        }
    }

    private static func environment(for executable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Bỏ API key để Claude Code dùng tài khoản đã đăng nhập (gói Pro/Max).
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        let binDir = (executable as NSString).deletingLastPathComponent
        env["PATH"] = "\(binDir):\(shellPATH)"
        return env
    }
}

private final class DataBox {
    var data = Data()
}
