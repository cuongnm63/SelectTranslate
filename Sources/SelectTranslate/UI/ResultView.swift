import AppKit
import SwiftUI

struct ResultView: View {
    @ObservedObject var session: TranslationSession
    @ObservedObject private var settings = AppSettings.shared
    var onClose: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.sourceText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)

                    Divider()

                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    if !session.translation.isEmpty {
                        CopyableBlock(text: session.translation) {
                            Text(session.translation)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    } else if session.isLoading {
                        Text("Đang dịch…").foregroundStyle(.secondary)
                    }

                    if !session.replies.isEmpty {
                        Text("Gợi ý trả lời")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(session.replies) { reply in
                            ReplyRow(reply: reply)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: PopupController.resultSize.width, height: PopupController.resultSize.height)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
        .clipShape(shape)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble")
                .foregroundStyle(Color.accentColor)
            Text(session.sourceLang.isEmpty ? "Claude" : "\(session.sourceLang) → \(settings.targetLanguage)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if session.isLoading {
                ProgressView().controlSize(.small)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Đóng (Esc)")
        }
    }
}

private struct ReplyRow: View {
    let reply: TranslationSession.Reply

    var body: some View {
        CopyableBlock(text: reply.text) {
            VStack(alignment: .leading, spacing: 4) {
                if !reply.tone.isEmpty {
                    Text(reply.tone)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Text(reply.text)
                    .font(.callout)
                    .textSelection(.enabled)
                if !reply.meaning.isEmpty {
                    Text(reply.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// Khối nội dung có nút copy ở góc phải.
private struct CopyableBlock<Content: View>: View {
    let text: String
    @ViewBuilder var content: () -> Content
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
