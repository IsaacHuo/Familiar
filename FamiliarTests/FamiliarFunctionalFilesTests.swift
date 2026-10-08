import Foundation
import SwiftData
import Testing
@testable import Familiar

private final class FunctionalFileBundleMarker: NSObject {}

@Suite("Real files and Project boundaries", .serialized)
struct FamiliarFunctionalFilesTests {
    private func fixture(_ name: String) throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/FunctionalFiles/" + name)
        if FileManager.default.fileExists(atPath: source.path) { return source }
        let bundle = Bundle(for: FunctionalFileBundleMarker.self)
        return try #require(bundle.url(forResource: name, withExtension: nil)
            ?? bundle.resourceURL?.appendingPathComponent("FunctionalFiles/" + name))
    }

    @Test("Real document imports keep original bytes, text, hash and scope", arguments: ["txt", "md", "csv", "docx", "pptx", "xlsx", "epub", "pdf", "rtf"])
    @MainActor func formats(_ format: String) async throws {
        let container = try FamiliarTestStore.make(name: "RealImport-" + format)
        let context = container.mainContext
        let project = FamiliarProject(name: "Import " + format)
        context.insert(project); try context.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FamiliarFileImportService(store: .init(rootURL: root))
        let input = try fixture("fc." + format)
        let file = try await service.importDocument(from: input, into: project, in: context)
        let version = try #require(file.latestVersion)
        #expect(version.extractedText.localizedCaseInsensitiveContains("PROBE"))
        #expect(version.projectID == project.id)
        let bytes = try Data(contentsOf: input)
        let saved = try Data(contentsOf: #require(service.quickLookURL(for: version)))
        #expect(saved == bytes)
        #expect(version.contentHash == FamiliarHash.sha256(bytes))
        #expect(version.extractedTextHash == FamiliarHash.sha256(version.extractedText))
        #expect(try FamiliarFileCatalogService().snapshots(projectID: UUID(), in: context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResource>()) == 0)
    }

    @Test("Scanned and mixed PDFs retain text and pixel evidence", arguments: ["fc-scanned.pdf", "fc-mixed.pdf"])
    func scannedAndMixed(_ name: String) async throws {
        let draft = try await FamiliarAttachmentStore.importDocument(from: fixture(name))
        defer { FamiliarAttachmentStore.remove(relativePath: draft.relativePath) }
        #expect(draft.usedOCR)
        #expect(draft.extractedText.contains("SCANNED PAGE PROBE"))
        if name == "fc-mixed.pdf" { #expect(draft.extractedText.contains("TEXT PAGE PROBE")) }
    }

    @Test("Protected and corrupt PDFs fail rather than becoming successful empty imports", arguments: ["fc-encrypted.pdf", "fc-corrupt.pdf"])
    func invalidPDF(_ name: String) async throws {
        await #expect(throws: (any Error).self) { try await FamiliarAttachmentStore.importDocument(from: fixture(name)) }
    }

    @Test("Missing destination Project rejects import before any new bytes or metadata")
    @MainActor func deletedDestination() throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let project = FamiliarProject(name: "Deleted")
        context.insert(project); try context.save()
        context.delete(project); try context.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FamiliarFileImportService(store: .init(rootURL: root))
        #expect(throws: FamiliarFileImportError.self) { try service.importPastedText("Unowned text", into: project, in: context) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try context.fetchCount(FetchDescriptor<FamiliarFileRecord>()) == 0)
    }

    @Test("An imported text File can be revised without changing its original bytes or identity")
    @MainActor func importedTextRevision() async throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let project = FamiliarProject(name: "Text revision")
        context.insert(project); try context.save()
        let resources = FamiliarProjectResourceStore()
        let generated = FamiliarFileStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {
            try? FileManager.default.removeItem(at: resources.rootURL.appendingPathComponent("Projects/" + project.id.uuidString))
            try? FileManager.default.removeItem(at: generated.rootURL)
        }
        let file = try FamiliarFileImportService(store: resources).importPastedText("Original imported text", title: "Note", into: project, in: context)
        let version = try #require(file.latestVersion)
        let snapshot = try #require(FamiliarFileCatalogService().snapshot(version))
        let input = FamiliarFileEditTool.Input(identifier: "file_" + version.id.uuidString, content: "Revised imported text", title: nil)
        let tool = FamiliarFileEditTool(store: generated)
        let outcome = try await tool.execute(input, context: .init(projectID: project.id, files: [snapshot]))
        guard case .action(let proposal) = outcome else { Issue.record("Expected revision approval"); return }
        try await proposal.validateBeforeCommit?()
        let committed = try await proposal.commit()
        let descriptor = try #require(committed.result.file)
        try FamiliarFileService(store: generated).persist(descriptor, in: context)
        #expect(file.versions.count == 2)
        #expect(file.latestVersion?.version == 2)
        #expect(try FamiliarFileByteReader.read(snapshot, projectID: project.id) == Data("Original imported text".utf8))
        #expect(try generated.read(relativePath: descriptor.relativePath) == Data("Revised imported text".utf8))
        await #expect(throws: FamiliarFileError.self) {
            try await tool.execute(input, context: .init(projectID: UUID(), files: [snapshot]))
        }
    }

    @Test("A file-backed Project and imported File reopen without changing content")
    @MainActor func diskReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reopen.store")
        let fileID: UUID
        do {
            let container = try FamiliarModelContainer.make(at: url, configurationName: "FCReopen")
            let context = container.mainContext
            let project = FamiliarProject(name: "Disk Project")
            context.insert(project); try context.save()
            let file = try FamiliarFileImportService(store: .init(rootURL: root.appendingPathComponent("Bytes")))
                .importPastedText("Persist across container reopening", into: project, in: context)
            fileID = file.id
        }
        let reopened = try FamiliarModelContainer.make(at: url, configurationName: "FCReopen")
        let file = try #require(reopened.mainContext.fetch(FetchDescriptor<FamiliarFileRecord>()).first { $0.id == fileID })
        #expect(file.latestVersion?.extractedText == "Persist across container reopening")
        let version = try #require(file.latestVersion)
        let bytes = try Data(contentsOf: #require(FamiliarProjectResourceStore(rootURL: root.appendingPathComponent("Bytes")).url(for: version.storageRelativePath)))
        #expect(FamiliarHash.sha256(bytes) == version.contentHash)
    }
}
