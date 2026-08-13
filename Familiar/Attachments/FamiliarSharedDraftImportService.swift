import Foundation

nonisolated struct FamiliarPreparedSharedDraft: Sendable {
    let sourceItem: FamiliarSharedInboxItem
    let text: String
    let attachments: [FamiliarAttachmentDraft]
    let firstImportErrorDescription: String?
}

nonisolated enum FamiliarSharedDraftImportService {
    static func prepareNext() async throws -> FamiliarPreparedSharedDraft? {
        guard let item = try FamiliarSharedInbox.pendingItems().first else { return nil }
        return await prepare(item)
    }

    static func prepareNext(rootURL: URL) async throws -> FamiliarPreparedSharedDraft? {
        guard let item = try FamiliarSharedInbox.pendingItems(rootURL: rootURL).first else { return nil }
        return await prepare(item)
    }

    static func consume(_ prepared: FamiliarPreparedSharedDraft) {
        FamiliarSharedInbox.remove(prepared.sourceItem)
    }

    static func discardPreparedAttachments(_ prepared: FamiliarPreparedSharedDraft) {
        FamiliarAttachmentStore.remove(relativePaths: prepared.attachments.map(\.relativePath))
    }

    private static func prepare(_ item: FamiliarSharedInboxItem) async -> FamiliarPreparedSharedDraft {
        var attachments: [FamiliarAttachmentDraft] = []
        var firstErrorDescription: String?
        for fileURL in item.fileURLs.prefix(FamiliarSharedInbox.maximumFiles) {
            do {
                attachments.append(try await FamiliarAttachmentStore.importDocument(from: fileURL))
            } catch {
                firstErrorDescription = firstErrorDescription ?? error.localizedDescription
            }
        }
        return FamiliarPreparedSharedDraft(
            sourceItem: item,
            text: item.payload.text,
            attachments: attachments,
            firstImportErrorDescription: firstErrorDescription
        )
    }
}
