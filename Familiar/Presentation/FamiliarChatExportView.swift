import SwiftUI

struct FamiliarChatExportView: View {
    @Environment(\.dismiss) private var dismiss
    let messages: [FamiliarMessageSnapshot]
    @State private var document: URL?
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: FamiliarSpacing.xLarge) {
                if let document {
                    Image(systemName: "doc.text").font(FamiliarTypography.largeTitle)
                    ShareLink(item: document) { Label(String(localized: "chat.export"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent)
                    Text(String(localized: "chat.export.footer")).font(.footnote).foregroundStyle(.secondary)
                } else if let errorMessage { Text(errorMessage) }
                else { ProgressView() }
            }
            .padding(FamiliarSpacing.section)
            .navigationTitle(String(localized: "chat.export"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.done")) { dismiss() } } }
            .task {
                do {
                    let body = messages.map { message in
                        let role = message.role == .user ? String(localized: "chat.export.user") : "Familiar"
                        let attachments = message.attachments.map { "- " + $0.filename }.joined(separator: "\n")
                        let sources = message.sources.map { "- [\($0.title)](\($0.url.absoluteString))" }.joined(separator: "\n")
                        return "## \(role)\n\n\(message.content)\n\n\(attachments)\n\n\(sources)"
                    }.joined(separator: "\n\n---\n\n")
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Familiar-chat-\(UUID().uuidString).md")
                    try Data(body.utf8).write(to: url, options: .atomic)
                    document = url
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
