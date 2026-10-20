import PhotosUI
import SwiftUI
import UIKit

enum FamiliarAttachmentImportSource {
    case file(URL), photo(PhotosPickerItem), camera(UIImage)
    var isImage: Bool { if case .file = self { false } else { true } }
    var name: String {
        if case .file(let url) = self { url.lastPathComponent }
        else { String(localized: "attachment.photos") }
    }
    func prepare() async throws -> FamiliarAttachmentDraft {
        switch self {
        case .file(let url): return try await FamiliarAttachmentStore.importDocument(from: url)
        case .camera(let image): return try await FamiliarAttachmentStore.importImage(image)
        case .photo(let item):
            guard let data = try await item.loadTransferable(type: Data.self) else { throw FamiliarAttachmentStoreError.sourceUnavailable }
            return try await FamiliarAttachmentStore.importImageData(data)
        }
    }
}

struct FamiliarAttachmentImport: Identifiable {
    enum Phase: Equatable { case preparing, failed(String) }
    let id: UUID
    let source: FamiliarAttachmentImportSource
    var attempt = UUID()
    var phase = Phase.preparing
}

nonisolated enum FamiliarAttachmentImportError: LocalizedError {
    case limit
    var errorDescription: String? { String(localized: "attachment.import_limit") }
}
