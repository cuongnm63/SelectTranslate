import Foundation

enum Prompt {
    static let maxInputChars = 8000

    static func system(target: String, suggestReplies: Bool) -> String {
        var rules = """
        You are a translation assistant inside a macOS app. The user selected some text on screen.
        Target language: \(target).

        Rules:
        - Detect the source language of the text.
        - Translate the text into \(target), naturally and accurately. Keep code, names, URLs, numbers and technical terms unchanged.
        - If the text is already in \(target), translate it into English instead.
        """

        if suggestReplies {
            rules += """

            - Then suggest exactly 3 short replies the user could send back, written in the SOURCE language \
            (the language of the selected text), with these tones in order: casual, neutral, professional.
            - For each reply give its meaning in \(target). Write tone labels in \(target).
            """
        }

        rules += """


        Output ONLY the following tagged format. No markdown, no extra text:
        <lang>source language name, written in \(target)</lang>
        <translation>the translation</translation>
        """

        if suggestReplies {
            rules += """

            <reply><tone>tone label</tone><text>reply in the source language</text><meaning>meaning in \(target)</meaning></reply>
            <reply>...</reply>
            <reply>...</reply>
            """
        }
        return rules
    }

    static func user(_ text: String) -> String {
        let clipped = text.count > maxInputChars ? String(text.prefix(maxInputChars)) + "…" : text
        return "<text>\n\(clipped)\n</text>"
    }
}

/// Parse output dạng tag, chịu được output đang stream dở.
enum ResponseParser {
    struct Parsed {
        var lang = ""
        var translation = ""
        var replies: [TranslationSession.Reply] = []
    }

    static func parse(_ output: String) -> Parsed {
        var parsed = Parsed()
        parsed.lang = partial("lang", in: output) ?? ""
        parsed.translation = partial("translation", in: output) ?? ""
        parsed.replies = complete("reply", in: output).enumerated().map { index, block in
            TranslationSession.Reply(
                id: index,
                tone: complete("tone", in: block).first ?? "",
                text: complete("text", in: block).first ?? "",
                meaning: complete("meaning", in: block).first ?? ""
            )
        }
        .filter { !$0.text.isEmpty }
        return parsed
    }

    /// Nội dung của tag, kể cả khi chưa đóng tag (đang stream).
    private static func partial(_ tag: String, in s: String) -> String? {
        guard let open = s.range(of: "<\(tag)>") else { return nil }
        let rest = s[open.upperBound...]
        if let close = rest.range(of: "</\(tag)>") {
            return String(rest[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var text = String(rest)
        // Bỏ phần tag đóng đang stream dở, ví dụ "...xin chào</transl"
        if let lt = text.lastIndex(of: "<"), !text[lt...].contains(">") {
            text = String(text[..<lt])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tất cả nội dung của các tag đã đóng hoàn chỉnh.
    private static func complete(_ tag: String, in s: String) -> [String] {
        var results: [String] = []
        var searchStart = s.startIndex
        while let open = s.range(of: "<\(tag)>", range: searchStart..<s.endIndex),
              let close = s.range(of: "</\(tag)>", range: open.upperBound..<s.endIndex) {
            results.append(String(s[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            searchStart = close.upperBound
        }
        return results
    }
}
