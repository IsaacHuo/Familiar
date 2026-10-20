import SwiftData
import SwiftUI
import UIKit

nonisolated struct FamiliarFileDeletionTarget: Identifiable, Equatable {
    let id: UUID
    let scope: FamiliarWorkScope
    let name: String
}

nonisolated struct FamiliarFileDeletionResult {
    var succeeded: Set<UUID> = []
    var failures: [UUID: String] = [:]
}

@MainActor enum FamiliarFileBatchDeletion {
    static func execute(_ targets: [FamiliarFileDeletionTarget], in context: ModelContext,
                        delete: (FamiliarFileRecord, ModelContext) throws -> Void = { try FamiliarFileCatalogService().delete($0, in: $1) }) async -> FamiliarFileDeletionResult {
        var result = FamiliarFileDeletionResult()
        for target in targets {
            do {
                let id = target.id
                var request = FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.id == id })
                request.fetchLimit = 1
                if let file = try context.fetch(request).first {
                    guard file.scope == target.scope else { throw FamiliarFileError.invalidPath }
                    try delete(file, context)
                }
                result.succeeded.insert(id)
            } catch { result.failures[target.id] = error.localizedDescription }
            await Task.yield()
        }
        return result
    }
}

struct FamiliarFileShareRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}
struct FamiliarFileShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// StorageFileListPanelComponent: 52pt row, 40pt icon, selection adds 48pt.
struct FamiliarTelegramFileRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let name: String
    let subtitle: String
    let snapshot: FamiliarFileSnapshot?
    let selecting: Bool
    let selected: Bool
    @Environment(\.familiarReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? FamiliarTheme.accent : .secondary)
                    .frame(width: 48).transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                if let snapshot, FamiliarFileCategory.classify(filename: snapshot.filename, mimeType: snapshot.mimeType) == .image {
                    FamiliarFileThumbnail(url: FamiliarFileByteReader.url(for: snapshot), identity: snapshot.reference.versionID.uuidString, symbol: "photo", side: 40).background(FamiliarImageSourceAnchor(id: snapshot.reference.versionID))
                } else {
                    FamiliarDocumentGlyph(extension: snapshot.map { URL(fileURLWithPath: $0.filename).pathExtension.uppercased() } ?? "", category: snapshot.map { .classify(filename: $0.filename, mimeType: $0.mimeType) } ?? .other)
                }
            }.frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body).foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }.padding(.leading, 22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6).frame(minHeight: 52)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: selecting)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FamiliarDocumentGlyph: View {
    let `extension`: String
    let category: FamiliarFileCategory
    private var color: Color {
        switch category { case .pdf, .presentation: .red; case .spreadsheet: .green; case .other: .orange; default: FamiliarTheme.accent }
    }
    var body: some View {
        ZStack {
            // Folded document outline from generateExtensionImage, same 40x40 coordinates.
            Path { p in
                p.move(to: .init(x: 6, y: 0)); p.addLine(to: .init(x: 26.76, y: 0))
                p.addQuadCurve(to: .init(x: 28.88, y: 0.88), control: .init(x: 28, y: 0))
                p.addLine(to: .init(x: 39.12, y: 11.12)); p.addQuadCurve(to: .init(x: 40, y: 13.24), control: .init(x: 40, y: 12))
                p.addLine(to: .init(x: 40, y: 34)); p.addQuadCurve(to: .init(x: 34, y: 40), control: .init(x: 40, y: 40))
                p.addLine(to: .init(x: 6, y: 40)); p.addQuadCurve(to: .init(x: 0, y: 34), control: .init(x: 0, y: 40))
                p.addLine(to: .init(x: 0, y: 6)); p.addQuadCurve(to: .init(x: 6, y: 0), control: .zero)
            }.fill(color.gradient)
            Path { p in p.move(to: .init(x: 27, y: 0)); p.addLine(to: .init(x: 27, y: 10)); p.addQuadCurve(to: .init(x: 30, y: 13), control: .init(x: 27, y: 13)); p.addLine(to: .init(x: 40, y: 13)); p.closeSubpath() }.fill(.white.opacity(0.25))
            Text(String(`extension`.prefix(4))).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).offset(y: 7)
        }.frame(width: 40, height: 40)
    }
}

struct FamiliarTelegramFilePressStyle: ButtonStyle {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? FamiliarTheme.hoverStrong : .clear)
            .animation(reduceMotion || configuration.isPressed ? nil : .easeOut(duration: 0.25), value: configuration.isPressed)
    }
}
